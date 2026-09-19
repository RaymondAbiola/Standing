// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {StdUtils} from "forge-std/StdUtils.sol";

import {Standing} from "../../src/Standing.sol";
import {Hold, HoldStatus} from "../../src/base/Escrow.sol";
import {Mandate} from "../../src/types/Mandate.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// Drives Standing with bounded random calls. Seeds fold into live state
/// rather than being used raw, so calls land on real mandates and holds.
///
/// Mandates come from a pool signed up front in setUp and activated on
/// demand. That matters: revocation is permanent and a mandate cannot be
/// recreated from the same terms, so without replenishment the fuzzer kills
/// every mandate in its first few calls and the run goes quiet. An earlier
/// version of this handler did exactly that, landing one charge and zero
/// finalizes across sixteen thousand calls.
contract StandingHandler is CommonBase, StdCheats, StdUtils {
    Standing public immutable STANDING;
    MockERC20 public immutable TOKEN;
    address public immutable OWNER;
    address public immutable TREASURY;

    address[] internal _payers;

    Mandate[] internal _pool;
    bytes[] internal _sigs;
    bool[] internal _activated;

    bytes32[] internal _mandates;
    uint256[] internal _holds;

    uint256 public holdsCreated;
    uint256 public finalizedTotal;
    uint256 public reversedTotal;

    // Reverts are swallowed so a bad seed does not end the run. These count
    // what actually landed, so the suite can prove it is not passing vacuously.
    uint256 public okActivate;
    uint256 public okCharge;
    uint256 public okFinalize;
    uint256 public okReverse;
    uint256 public okRevoke;
    uint256 public okRevokeAll;
    uint256 public okSweep;

    constructor(
        Standing standing,
        MockERC20 token,
        address owner,
        address treasury,
        address[] memory payers
    ) {
        STANDING = standing;
        TOKEN = token;
        OWNER = owner;
        TREASURY = treasury;
        _payers = payers;
    }

    function seed(Mandate memory m, bytes memory sig) external {
        _pool.push(m);
        _sigs.push(sig);
        _activated.push(false);
    }

    function poolSize() external view returns (uint256) {
        return _pool.length;
    }

    function holdCount() external view returns (uint256) {
        return _holds.length;
    }

    function holdAt(uint256 i) external view returns (uint256) {
        return _holds[i];
    }

    function mandateCount() external view returns (uint256) {
        return _mandates.length;
    }

    function mandateAt(uint256 i) external view returns (bytes32) {
        return _mandates[i];
    }

    /// Brings a pre-signed mandate onchain, replenishing what revocation
    /// removes.
    function activate(uint256 poolSeed) external {
        uint256 n = _pool.length;
        if (n == 0) return;

        uint256 start = poolSeed % n;
        for (uint256 k; k < n; ++k) {
            uint256 i = (start + k) % n;
            if (_activated[i]) continue;

            _activated[i] = true;
            try STANDING.createMandate(_pool[i], _sigs[i]) returns (bytes32 id) {
                _mandates.push(id);
                okActivate += 1;
            } catch {}
            return;
        }
    }

    /// Scans from the seed for a mandate that can actually be billed right
    /// now. Picking blindly wastes almost every call on a revoked mandate or
    /// one still inside its interval, which leaves the invariants unexercised.
    function charge(uint256 mandateSeed, uint256 amountSeed) external {
        uint256 n = _mandates.length;
        if (n == 0) return;

        uint256 amount = bound(amountSeed, 1, 30e6);
        uint256 start = mandateSeed % n;

        for (uint256 k; k < n; ++k) {
            bytes32 id = _mandates[(start + k) % n];
            if (!STANDING.isChargeable(id, amount)) continue;

            try STANDING.charge(id, amount) returns (uint256 holdId) {
                _holds.push(holdId);
                holdsCreated += 1;
                okCharge += 1;
            } catch {}
            return;
        }
    }

    function finalize(uint256 holdSeed) external {
        uint256 n = _holds.length;
        if (n == 0) return;

        uint256 start = holdSeed % n;
        for (uint256 k; k < n; ++k) {
            uint256 holdId = _holds[(start + k) % n];
            if (!STANDING.isHoldUnlocked(holdId)) continue;

            uint256 amount = STANDING.getHold(holdId).amount;
            try STANDING.finalize(holdId) {
                finalizedTotal += amount;
                okFinalize += 1;
            } catch {}
            return;
        }
    }

    function reverse(uint256 holdSeed) external {
        uint256 n = _holds.length;
        if (n == 0) return;

        uint256 start = holdSeed % n;
        for (uint256 k; k < n; ++k) {
            uint256 holdId = _holds[(start + k) % n];
            Hold memory h = STANDING.getHold(holdId);
            if (h.status != HoldStatus.Held || block.timestamp >= h.unlockAt) continue;
            // The ceiling gates most reversals now, so scanning without it
            // spends the call on a hold this payer cannot touch.
            if (h.amount > STANDING.reversalCeiling(h.payer)) continue;

            vm.prank(h.payer);
            try STANDING.reverse(holdId) {
                reversedTotal += h.amount;
                okReverse += 1;
            } catch {}
            return;
        }
    }

    function setFee(uint256 bpsSeed) external {
        uint16 bps = uint16(bound(bpsSeed, 0, STANDING.MAX_FEE_BPS()));
        vm.prank(OWNER);
        try STANDING.setFeeBps(bps) {} catch {}
    }

    function sweep() external {
        vm.prank(OWNER);
        try STANDING.sweepFees(address(TOKEN), TREASURY) {
            okSweep += 1;
        } catch {}
    }

    function revokeMandate(uint256 mandateSeed) external {
        if (_mandates.length == 0) return;
        bytes32 id = _mandates[mandateSeed % _mandates.length];
        address payer = STANDING.getMandate(id).terms.payer;

        vm.prank(payer);
        try STANDING.revokeMandate(id) {
            okRevoke += 1;
        } catch {}
    }

    function revokeAll(uint256 payerSeed) external {
        address payer = _payers[payerSeed % _payers.length];
        vm.prank(payer);
        try STANDING.revokeAll() {
            okRevokeAll += 1;
        } catch {}
    }

    /// Without this, windows never close and cadence never elapses, so most
    /// of the state machine stays unreachable.
    function warp(uint256 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 1 hours, 20 days));
    }
}
