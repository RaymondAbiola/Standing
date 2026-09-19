// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Standing} from "../../src/Standing.sol";
import {Hold, HoldStatus} from "../../src/base/Escrow.sol";
import {ChargeKind, Mandate} from "../../src/types/Mandate.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockPermit2} from "../mocks/MockPermit2.sol";
import {StandingHandler} from "./StandingHandler.sol";

contract StandingInvariantTest is Test {
    Standing internal std;
    MockPermit2 internal permit2;
    MockERC20 internal token;
    StandingHandler internal handler;

    address internal owner = makeAddr("owner");
    address internal treasury = makeAddr("treasury");
    address internal merchantA = makeAddr("merchantA");
    address internal merchantB = makeAddr("merchantB");

    address[] internal payers;
    uint256 internal constant MINT_EACH = 1_000_000e6;
    uint256 internal totalMinted;

    function setUp() public {
        vm.warp(1_000_000);
        permit2 = new MockPermit2();
        std = new Standing(address(permit2), owner);
        token = new MockERC20(0);

        uint256[] memory keys = new uint256[](3);
        (address p0, uint256 k0) = makeAddrAndKey("payer0");
        (address p1, uint256 k1) = makeAddrAndKey("payer1");
        (address p2, uint256 k2) = makeAddrAndKey("payer2");
        payers = [p0, p1, p2];
        keys[0] = k0;
        keys[1] = k1;
        keys[2] = k2;

        for (uint256 i; i < payers.length; ++i) {
            token.mint(payers[i], MINT_EACH);
            totalMinted += MINT_EACH;
            vm.startPrank(payers[i]);
            token.approve(address(permit2), type(uint256).max);
            permit2.approve(address(token), address(std), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }

        handler = new StandingHandler(std, token, owner, treasury, payers);

        // Pre-sign a pool the handler activates on demand. Signing during the
        // run would dominate the gas budget, and without replenishment the
        // fuzzer revokes every mandate within its first few calls.
        for (uint256 i; i < 36; ++i) {
            uint256 pi = i % payers.length;
            _seed(
                payers[pi],
                keys[pi],
                i % 2 == 0 ? merchantA : merchantB,
                i % 5 == 0 ? ChargeKind.Postpaid : ChargeKind.Prepaid,
                i % 3 == 0 ? 1 days : 7 days,
                i % 7 == 0 ? 3 : 0,
                bytes32(i + 1)
            );
        }

        // `seed` is setup-only. Left targetable, the fuzzer calls it with
        // garbage and pollutes the pool it is supposed to draw from.
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = StandingHandler.activate.selector;
        selectors[1] = StandingHandler.charge.selector;
        selectors[2] = StandingHandler.finalize.selector;
        selectors[3] = StandingHandler.reverse.selector;
        selectors[4] = StandingHandler.setFee.selector;
        selectors[5] = StandingHandler.sweep.selector;
        selectors[6] = StandingHandler.revokeMandate.selector;
        selectors[7] = StandingHandler.revokeAll.selector;
        selectors[8] = StandingHandler.warp.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function _seed(
        address payer,
        uint256 key,
        address merchant,
        ChargeKind kind,
        uint64 minInterval,
        uint32 maxCharges,
        bytes32 salt
    ) internal {
        Mandate memory m = Mandate({
            payer: payer,
            merchant: merchant,
            token: address(token),
            maxAmount: 30e6,
            minInterval: minInterval,
            startsAt: uint64(block.timestamp),
            expiresAt: type(uint64).max,
            maxCharges: maxCharges,
            chargeKind: kind,
            salt: salt
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, std.mandateDigest(m));
        handler.seed(m, abi.encodePacked(r, s, v));
    }

    /// The contract must always be able to honour every open hold and every
    /// fee it has taken. This is the one that matters: if it breaks, someone
    /// cannot be paid.
    function invariant_solvent() public view {
        assertGe(
            token.balanceOf(address(std)),
            std.totalHeld(address(token)) + std.accruedFees(address(token)),
            "insolvent"
        );
    }

    /// Catches accounting drift: the accumulator must agree with the holds it
    /// claims to summarise.
    function invariant_openHoldsSumToTotalHeld() public view {
        uint256 sum;
        uint256 n = handler.holdCount();
        for (uint256 i; i < n; ++i) {
            Hold memory h = std.getHold(handler.holdAt(i));
            if (h.status == HoldStatus.Held) sum += h.amount;
        }
        assertEq(sum, std.totalHeld(address(token)), "totalHeld drifted from open holds");
    }

    /// No id may be skipped or reused, so a hold can never be created without
    /// being accounted for.
    function invariant_noOrphanHoldIds() public view {
        uint256 next = std.nextHoldId();
        assertEq(next, handler.holdsCreated() + 1, "id counter out of step");
        for (uint256 id = 1; id < next; ++id) {
            assertTrue(std.getHold(id).status != HoldStatus.None, "orphan id");
        }
    }

    /// Nothing is created or destroyed. Every token minted is held by exactly
    /// one of the parties, which catches any leak the per-hold accounting
    /// might miss.
    function invariant_tokenConservation() public view {
        uint256 held = token.balanceOf(address(std));
        uint256 out = token.balanceOf(merchantA) + token.balanceOf(merchantB) + token.balanceOf(treasury);
        uint256 payerSide;
        for (uint256 i; i < payers.length; ++i) {
            payerSide += token.balanceOf(payers[i]);
        }
        assertEq(payerSide + out + held, totalMinted, "tokens leaked or created");
    }

    /// Every successful charge books exactly one hold, which ties the mandate
    /// side of the contract to the escrow side.
    function invariant_chargeCountsMatchHoldsCreated() public view {
        uint256 charges;
        uint256 n = handler.mandateCount();
        for (uint256 i; i < n; ++i) {
            charges += std.getMandate(handler.mandateAt(i)).chargeCount;
        }
        assertEq(charges, handler.holdsCreated(), "charges and holds disagree");
    }

    /// Standing must equal what was actually settled. Every finalized hold
    /// credits the payer exactly its gross amount, and nothing else does.
    function invariant_standingMatchesSettlements() public view {
        uint256 credited;
        for (uint256 i; i < payers.length; ++i) {
            credited += std.standingOf(payers[i]).cumulativeCleanSettled;
        }
        assertEq(credited, handler.finalizedTotal(), "standing drifted from settlements");
    }

    /// A settled hold's outcome must match what left the contract, so fees
    /// can never exceed the ceiling on what was actually finalised.
    function invariant_feesWithinCeiling() public view {
        uint256 ceiling = (handler.finalizedTotal() * std.MAX_FEE_BPS()) / 10_000;
        assertLe(
            std.accruedFees(address(token)) + token.balanceOf(treasury), ceiling + 1, "fees above ceiling"
        );
    }

    /// Guards against a vacuous pass. Invariants are evaluated before the
    /// first call, so this cannot be one of them: it belongs in the hook that
    /// runs once a sequence has finished.
    ///
    /// It matters. An earlier version of this handler let the fuzzer revoke
    /// every mandate in its first few calls with no way to replenish, and the
    /// suite passed with one charge and zero finalizes across sixteen
    /// thousand calls.
    function afterInvariant() public view {
        // This hook runs per sequence, so anything probabilistic flakes.
        // Requiring both settlement paths in every single run does; requiring
        // at least one does not. Measured coverage across a full pass is
        // roughly 22 charges, 15 reversals and 5 finalizes per run.
        assertGt(handler.okActivate(), 0, "no mandate ever activated");
        assertGt(handler.okCharge(), 0, "no charge ever landed");
        assertGt(handler.okFinalize() + handler.okReverse(), 0, "no hold ever settled");

        console.log("activated", handler.okActivate());
        console.log("charges  ", handler.okCharge());
        console.log("finalized", handler.okFinalize());
        console.log("reversed ", handler.okReverse());
        console.log("revoked  ", handler.okRevoke());
        console.log("swept    ", handler.okSweep());
    }
}
