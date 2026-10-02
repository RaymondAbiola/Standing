// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Standing} from "../src/Standing.sol";
import {CANONICAL_PERMIT2} from "../src/base/Permit2Puller.sol";
import {ChargeKind, Mandate} from "../src/types/Mandate.sol";
import {DemoUSDC} from "./DemoUSDC.sol";

interface IPermit2Approve {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

/// Leaves a live, reversible hold on chain so a reversal can be demonstrated
/// without waiting out a settlement window.
///
/// The obstacle is not the window, which is five days and generous. It is
/// vesting: a reversal needs three clean settlements first, and each prepaid
/// settlement is gated by that same five day window, so the honest route to a
/// first reversal takes over two weeks.
///
/// Postpaid charges settle with a zero window, and `finalize` credits standing
/// whatever the charge kind, because the payer moved the value cleanly either
/// way. So three postpaid cycles vest the payer in one block, and the prepaid
/// charge that follows is immediately reversible for the next five days.
///
/// Uses one address as both payer and merchant, which the contract permits.
contract DemoFlow is Script {
    uint256 internal constant CYCLE = 30e6;

    /// Salts are derived per run, not fixed.
    ///
    /// A mandate id is the hash of its terms and records are never cleared, so
    /// fixed salts make the script single-use per chain: a second run reverts
    /// with MandateExists. That matters because `revokeAll` bumps the payer
    /// epoch and kills every outstanding mandate, which is an easy button to
    /// press by accident, and recovery means running this again.
    uint256 internal runSeed;

    function run() external {
        Standing standing = Standing(vm.envAddress("STANDING"));
        DemoUSDC token = DemoUSDC(vm.envAddress("DEMO_TOKEN"));
        uint256 key = _privateKey();
        address me = vm.addr(key);

        runSeed = uint256(keccak256(abi.encode(block.timestamp, block.number, me)));

        vm.startBroadcast(key);

        token.mint(me, 100_000e6);
        token.approve(CANONICAL_PERMIT2, type(uint256).max);
        IPermit2Approve(CANONICAL_PERMIT2)
            .approve(
                address(token), address(standing), uint160(200_000e6), uint48(block.timestamp + 365 days)
            );

        // Three postpaid cycles, each its own mandate rather than one charged
        // three times. `minInterval` cannot be zero, and these all land in the
        // same broadcast and so can share a block timestamp, which would make
        // the second charge on a single mandate fail the cadence floor.
        //
        // They are revoked straight after settling. Their only job is to vest
        // the payer, and leaving them active makes four identical-looking rows
        // in the merchant list where only one is the live subscription.
        for (uint256 i; i < 3; ++i) {
            Mandate memory warm = _terms(me, address(token), ChargeKind.Postpaid, bytes32(runSeed + i));
            bytes32 id = standing.createMandate(warm, _sign(key, standing, warm));
            uint256 holdId = standing.charge(id, CYCLE);
            standing.finalize(holdId);
            standing.revokeMandate(id);
        }

        Mandate memory live = _terms(me, address(token), ChargeKind.Prepaid, bytes32(runSeed + 100));
        bytes32 liveId = standing.createMandate(live, _sign(key, standing, live));
        uint256 reversible = standing.charge(liveId, CYCLE);

        vm.stopBroadcast();

        console.log("payer and merchant  ", me);
        console.log("vested              ", standing.isVested(me));
        console.log("clean settlements   ", standing.cleanSettlementsOf(me));
        console.log("reversal ceiling    ", standing.reversalCeiling(me));
        console.log("reversible hold id  ", reversible);
        console.log("can reverse it now  ", standing.canReverse(reversible, me));
        console.log("window closes at    ", standing.getHold(reversible).unlockAt);
    }

    /// `--private-key` accepts a key with or without the 0x prefix, but
    /// `vm.envUint` insists on it. Tolerate both rather than making the demo
    /// depend on how the key happens to be written in .env.
    function _privateKey() internal view returns (uint256) {
        string memory raw = vm.envString("PRIVATE_KEY");
        bytes memory b = bytes(raw);
        bool prefixed = b.length > 1 && b[0] == "0" && (b[1] == "x" || b[1] == "X");
        return vm.parseUint(prefixed ? raw : string.concat("0x", raw));
    }

    function _terms(address who, address token, ChargeKind kind, bytes32 salt)
        internal
        view
        returns (Mandate memory)
    {
        return Mandate({
            payer: who,
            merchant: who,
            token: token,
            maxAmount: CYCLE,
            minInterval: 1,
            startsAt: uint64(block.timestamp),
            expiresAt: type(uint64).max,
            maxCharges: 0,
            chargeKind: kind,
            salt: salt
        });
    }

    function _sign(uint256 key, Standing standing, Mandate memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, standing.mandateDigest(m));
        return abi.encodePacked(r, s, v);
    }
}
