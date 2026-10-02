// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Standing} from "../src/Standing.sol";
import {AcceptanceBlock, MerchantRegistry} from "../src/base/MerchantRegistry.sol";
import {ChargeKind, Mandate} from "../src/types/Mandate.sol";
import {ReversalBlock} from "../src/types/Reversal.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";

/// A merchant's two levers: who it will serve, and how much of a stranger's
/// imported ceiling it will honour.
contract AcceptancePolicyTest is Test {
    uint256 internal constant CYCLE = 30e6;

    /// Typed at declaration so the policy calls need no inline casts, which
    /// the linter cannot prove safe even when they are.
    uint96 internal constant TRUST = 90e6;
    uint96 internal constant SMALL_CAP = 5e6;
    uint96 internal constant FULL_CAP = 30e6;

    Standing internal std;
    MockPermit2 internal permit2;
    MockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal merchant = makeAddr("merchant");
    address internal altMerchant = makeAddr("altMerchant");

    uint256 internal payerKey;
    address internal payer;
    uint64 internal window;
    uint256 internal salt;

    function setUp() public {
        vm.warp(1_000_000);
        permit2 = new MockPermit2();
        std = new Standing(address(permit2), owner);
        token = new MockERC20(0);
        (payer, payerKey) = makeAddrAndKey("payer");
        window = std.MAX_MERCHANT_WINDOW();

        token.mint(payer, 10_000_000e6);
        vm.startPrank(payer);
        token.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token), address(std), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _terms(address mrc) internal returns (Mandate memory) {
        salt += 1;
        return Mandate({
            payer: payer,
            merchant: mrc,
            token: address(token),
            maxAmount: CYCLE,
            minInterval: 1,
            startsAt: uint64(block.timestamp),
            expiresAt: type(uint64).max,
            maxCharges: 0,
            chargeKind: ChargeKind.Prepaid,
            salt: bytes32(salt)
        });
    }

    function _sign(Mandate memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, std.mandateDigest(m));
        return abi.encodePacked(r, s, v);
    }

    function _create(address mrc) internal returns (bytes32) {
        Mandate memory m = _terms(mrc);
        return std.createMandate(m, _sign(m));
    }

    /// Settles `rounds` postpaid cycles with `mrc`, advancing time by seconds
    /// rather than days. Needed when the point is to settle inside an open
    /// hold's window, which prepaid settlements would outlast.
    function _settleFastWith(address mrc, uint256 rounds) internal {
        salt += 1;
        Mandate memory m = Mandate({
            payer: payer,
            merchant: mrc,
            token: address(token),
            maxAmount: CYCLE,
            minInterval: 1,
            startsAt: uint64(block.timestamp),
            expiresAt: type(uint64).max,
            maxCharges: 0,
            chargeKind: ChargeKind.Postpaid,
            salt: bytes32(salt)
        });
        bytes32 id = std.createMandate(m, _sign(m));

        for (uint256 i; i < rounds; ++i) {
            std.finalize(std.charge(id, CYCLE));
            vm.warp(block.timestamp + 1);
        }
    }

    /// Settles `rounds` clean cycles with `mrc`, which is what builds both the
    /// global ceiling and the per-pair figure.
    function _settleWith(address mrc, uint256 rounds) internal {
        bytes32 id = _create(mrc);
        for (uint256 i; i < rounds; ++i) {
            uint256 h = std.charge(id, CYCLE);
            vm.warp(block.timestamp + window);
            std.finalize(h);
            vm.warp(block.timestamp + 1);
        }
    }

    // --- admission ---

    function test_noPolicyAcceptsAnyone() public {
        assertFalse(std.acceptancePolicyOf(merchant).set);
        assertTrue(std.wouldAccept(merchant, payer));
        _create(merchant);
    }

    function test_minCleanSettlementsGatesAdmission() public {
        vm.prank(merchant);
        std.setAcceptancePolicy(3, 255, false, 0, 0);

        assertEq(uint8(std.acceptanceBlocker(merchant, payer)), uint8(AcceptanceBlock.StandingTooLow));

        Mandate memory m = _terms(merchant);
        bytes memory sig = _sign(m);
        vm.expectRevert(abi.encodeWithSelector(Standing.PayerStandingTooLow.selector, uint32(0), uint32(3)));
        std.createMandate(m, sig);

        // earn it somewhere else, then come back
        _settleWith(altMerchant, 3);
        assertTrue(std.wouldAccept(merchant, payer));
        _create(merchant);
    }

    function test_reversalLimitGatesAdmission() public {
        _settleWith(merchant, 3);
        bytes32 id = _create(merchant);
        uint256 h = std.charge(id, CYCLE);
        vm.prank(payer);
        std.reverse(h);
        assertEq(std.reversalsInWindow(payer), 1);

        vm.prank(merchant);
        std.setAcceptancePolicy(0, 0, false, 0, 0);

        assertEq(uint8(std.acceptanceBlocker(merchant, payer)), uint8(AcceptanceBlock.TooManyReversals));

        Mandate memory m = _terms(merchant);
        bytes memory sig = _sign(m);
        vm.expectRevert(abi.encodeWithSelector(Standing.PayerTooManyReversals.selector, uint8(1), uint8(0)));
        std.createMandate(m, sig);
    }

    function test_clearReopensAdmission() public {
        vm.prank(merchant);
        std.setAcceptancePolicy(9, 0, true, 0, 0);
        assertFalse(std.wouldAccept(merchant, payer));

        vm.prank(merchant);
        std.clearAcceptancePolicy();
        assertFalse(std.acceptancePolicyOf(merchant).set);
        assertTrue(std.wouldAccept(merchant, payer));
        _create(merchant);
    }

    /// A merchant sets terms for itself only.
    function test_policyIsPerMerchant() public {
        vm.prank(merchant);
        std.setAcceptancePolicy(5, 0, true, 0, 0);

        assertFalse(std.wouldAccept(merchant, payer));
        assertTrue(std.wouldAccept(altMerchant, payer));

        vm.prank(altMerchant);
        std.setAcceptancePolicy(0, 255, false, 0, 0);
        assertEq(std.acceptancePolicyOf(merchant).minCleanSettlements, 5, "untouched");
    }

    function testFuzz_admissionProbeAgreesWithGuard(uint32 minClean, uint8 maxRev, bool refuse) public {
        vm.prank(merchant);
        std.setAcceptancePolicy(uint32(bound(minClean, 0, 4)), maxRev, refuse, 0, 0);

        Mandate memory m = _terms(merchant);
        bytes memory sig = _sign(m);

        if (std.wouldAccept(merchant, payer)) {
            std.createMandate(m, sig);
        } else {
            vm.expectRevert();
            std.createMandate(m, sig);
        }
    }

    // --- the reversal cap ---

    function test_perPairSettlementIsTracked() public {
        _settleWith(merchant, 2);
        assertEq(std.cleanSettledWith(payer, merchant), 2 * CYCLE);
        assertEq(std.cleanSettledWith(payer, altMerchant), 0, "per pair, not global");
        assertEq(std.standingOf(payer).cumulativeCleanSettled, 2 * CYCLE);
    }

    function test_noPolicyMeansGlobalCeilingApplies() public {
        _settleWith(altMerchant, 3);
        assertEq(std.reversalCeiling(payer), CYCLE);
        assertEq(std.effectiveReversalCeiling(payer, merchant), CYCLE, "nothing capped");
    }

    /// A cap only binds while the payer is below the threshold, so a cap with
    /// no threshold would never apply. Accepting it silently would let a
    /// merchant believe it was protected when it was not, so it is refused.
    function test_capWithoutThresholdIsRefused() public {
        vm.prank(merchant);
        vm.expectRevert(MerchantRegistry.CapWithoutThreshold.selector);
        std.setAcceptancePolicy(0, 255, false, SMALL_CAP, 0);
    }

    /// The attack the cap exists for. A payer manufactures a ceiling by
    /// settling to an address it controls, then tries to spend it somewhere
    /// real. The global ceiling is genuine; what it buys at this merchant is
    /// what this merchant agreed to honour.
    function test_importedCeilingIsCappedUntilTrusted() public {
        _settleWith(altMerchant, 3);
        assertEq(std.reversalCeiling(payer), CYCLE, "global ceiling is built");
        assertEq(std.cleanSettledWith(payer, merchant), 0, "but none of it was settled here");

        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, SMALL_CAP, TRUST);

        assertEq(std.effectiveReversalCeiling(payer, merchant), 5e6, "capped at what the merchant allowed");

        bytes32 id = _create(merchant);
        uint256 big = std.charge(id, CYCLE);
        assertEq(uint8(std.reversalBlocker(big, payer)), uint8(ReversalBlock.AboveMerchantCap));

        vm.prank(payer);
        vm.expectRevert(
            abi.encodeWithSelector(Standing.AboveMerchantCap.selector, 5e6, uint256(0), uint256(3 * CYCLE))
        );
        std.reverse(big);
    }

    function test_withinTheCapStillWorks() public {
        _settleWith(altMerchant, 3);
        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, SMALL_CAP, TRUST);

        bytes32 id = _create(merchant);
        uint256 small = std.charge(id, 5e6);
        assertTrue(std.canReverse(small, payer));

        vm.prank(payer);
        std.reverse(small);
    }

    /// Once the payer has genuinely settled enough here, the cap lifts and the
    /// full global ceiling applies. Portable standing is deferred, not denied.
    function test_capLiftsOnceTrustThresholdIsMet() public {
        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, SMALL_CAP, TRUST);

        _settleWith(merchant, 3);

        assertEq(std.cleanSettledWith(payer, merchant), 3 * CYCLE);
        assertEq(std.effectiveReversalCeiling(payer, merchant), std.reversalCeiling(payer), "cap lifted");

        bytes32 id = _create(merchant);
        uint256 h = std.charge(id, CYCLE);
        vm.prank(payer);
        std.reverse(h);
    }

    /// A merchant that trusts nothing imported sets a cap of zero.
    function test_zeroCapRefusesEverythingUntilTrusted() public {
        _settleWith(altMerchant, 3);
        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, 0, TRUST);

        assertEq(std.effectiveReversalCeiling(payer, merchant), 0);

        bytes32 id = _create(merchant);
        uint256 h = std.charge(id, 1);
        assertEq(uint8(std.reversalBlocker(h, payer)), uint8(ReversalBlock.AboveMerchantCap));
    }

    /// The cap narrows an imported ceiling and never widens one. A generous cap
    /// cannot hand a payer more than it actually earned globally.
    function test_capNeverExceedsTheGlobalCeiling() public {
        _settleWith(altMerchant, 3);
        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, type(uint96).max, type(uint96).max);

        assertEq(
            std.effectiveReversalCeiling(payer, merchant),
            std.reversalCeiling(payer),
            "bounded by the global ceiling"
        );
    }

    function test_capIsPerMerchant() public {
        _settleWith(altMerchant, 3);
        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, uint96(1e6), TRUST);

        assertEq(std.effectiveReversalCeiling(payer, merchant), 1e6);
        assertEq(std.effectiveReversalCeiling(payer, altMerchant), CYCLE, "the other merchant set nothing");
    }

    /// The merchant's terms are frozen into the hold at charge time.
    ///
    /// Without that a merchant could take the money and then tighten its policy
    /// to nothing, stripping the payer's remedy on a charge already in escrow,
    /// which would defeat the window entirely. Same reason the fee and the
    /// mandate terms are snapshotted.
    function test_tighteningPolicyCannotStripAnOpenHold() public {
        _settleWith(altMerchant, 3);

        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, FULL_CAP, TRUST);

        bytes32 id = _create(merchant);
        uint256 h = std.charge(id, CYCLE);
        assertTrue(std.canReverse(h, payer), "reversible when charged");

        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, 0, TRUST);

        assertTrue(std.canReverse(h, payer), "still reversible, terms were frozen");
        vm.prank(payer);
        std.reverse(h);
    }

    /// The freeze cuts both ways: loosening afterwards does not reach an open
    /// hold either. Terms are whatever they were when the money was taken.
    function test_looseningPolicyDoesNotReachAnOpenHold() public {
        _settleWith(altMerchant, 3);

        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, 1, TRUST);

        bytes32 id = _create(merchant);
        uint256 h = std.charge(id, CYCLE);
        assertFalse(std.canReverse(h, payer));

        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, FULL_CAP, TRUST);

        assertFalse(std.canReverse(h, payer), "the hold keeps its booked terms");
    }

    /// Only the merchant's side is frozen. A payer who settles more with this
    /// merchant during the window clears the cap on a hold already open, since
    /// that is the payer's own progress rather than the merchant's terms.
    function test_payerCanClearTheCapDuringTheWindow() public {
        _settleWith(altMerchant, 3);

        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, 1, TRUST);

        bytes32 capped = _create(merchant);
        uint256 h = std.charge(capped, CYCLE);
        assertFalse(std.canReverse(h, payer), "capped at first");

        // Postpaid, so this lands inside the open hold's window.
        _settleFastWith(merchant, 3);

        assertGe(std.cleanSettledWith(payer, merchant), TRUST);
        assertTrue(std.canReverse(h, payer), "cap lifted by the payer's own settlements");
    }

    function testFuzz_reversalProbeAgreesWithGuard(uint96 cap, uint96 threshold, uint256 amountSeed) public {
        _settleWith(altMerchant, 3);

        // Modulo against uint96 literals, so nothing is cast. The threshold is
        // always nonzero, since a cap without one is refused.
        uint96 capped = cap % 30_000_001;
        uint96 thresh = (threshold % 150_000_000) + 1;

        vm.prank(merchant);
        std.setAcceptancePolicy(0, 255, false, capped, thresh);

        bytes32 id = _create(merchant);
        uint256 amount = bound(amountSeed, 1, CYCLE);
        uint256 h = std.charge(id, amount);

        bool allowed = std.canReverse(h, payer);
        vm.prank(payer);
        if (allowed) {
            std.reverse(h);
        } else {
            vm.expectRevert();
            std.reverse(h);
        }
    }
}
