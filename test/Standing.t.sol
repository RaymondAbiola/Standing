// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Standing} from "../src/Standing.sol";
import {Escrow, Hold, HoldStatus} from "../src/base/Escrow.sol";
import {MandateRegistry} from "../src/base/MandateRegistry.sol";
import {Permit2Puller} from "../src/base/Permit2Puller.sol";
import {ChargeKind, Mandate} from "../src/types/Mandate.sol";
import {ReversalBlock} from "../src/types/Reversal.sol";
import {UnsafeOrderingHarness} from "./harness/UnsafeOrderingHarness.sol";
import {MockERC1271Signer} from "./mocks/MockERC1271Signer.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";
import {IChargeable, ReenteringToken} from "./mocks/ReenteringToken.sol";

contract StandingTest is Test {
    Standing internal std;
    MockPermit2 internal permit2;
    MockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal merchant = makeAddr("merchant");
    address internal merchantB = makeAddr("merchantB");
    address internal merchantC = makeAddr("merchantC");
    uint256 internal payerKey;
    address internal payer;

    uint48 internal permitExpiry;
    /// The longest any hold waits. Warping by this always clears a hold
    /// whatever tier the merchant has reached, so tests that only need the
    /// window closed anchor here rather than on a live value.
    uint64 internal window;

    function setUp() public {
        vm.warp(1_000_000);
        permit2 = new MockPermit2();
        std = new Standing(address(permit2), owner);
        token = new MockERC20(0);
        (payer, payerKey) = makeAddrAndKey("payer");
        window = std.MAX_MERCHANT_WINDOW();

        // Deliberately shorter than the mandate window, so a test can expire
        // the Permit2 allowance while the mandate itself is still live.
        permitExpiry = uint48(block.timestamp + 1000 days);
        _arm(payer, token);
    }

    function _arm(address who, MockERC20 tok) internal {
        tok.mint(who, 100_000e6);
        vm.startPrank(who);
        tok.approve(address(permit2), type(uint256).max);
        permit2.approve(address(tok), address(std), 50_000e6, permitExpiry);
        vm.stopPrank();
    }

    function _terms(address p, address tok, ChargeKind kind, bytes32 salt)
        internal
        view
        returns (Mandate memory)
    {
        return _termsFor(p, merchant, tok, kind, salt);
    }

    function _termsFor(address p, address mrc, address tok, ChargeKind kind, bytes32 salt)
        internal
        view
        returns (Mandate memory)
    {
        return Mandate({
            payer: p,
            merchant: mrc,
            token: tok,
            maxAmount: 30e6,
            minInterval: 30 days,
            startsAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + 3650 days),
            maxCharges: 0,
            chargeKind: kind,
            salt: salt
        });
    }

    function _create(Mandate memory m) internal returns (bytes32) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, std.mandateDigest(m));
        return std.createMandate(m, abi.encodePacked(r, s, v));
    }

    function _mandate() internal returns (bytes32) {
        return _create(_terms(payer, address(token), ChargeKind.Prepaid, bytes32(uint256(1))));
    }

    /// Settles clean cycles until the payer can actually reverse `target`.
    ///
    /// Both gates have to be satisfied, and they are independent: vesting
    /// needs a number of clean cycles, the ceiling needs a value. A single
    /// large settlement clears the ceiling but not vesting.
    function _buildStanding(bytes32 id, uint256 target) internal {
        while (!std.isVested(payer) || std.reversalCeiling(payer) < target) {
            uint256 h = std.charge(id, 30e6);
            vm.warp(block.timestamp + window);
            std.finalize(h);
            vm.warp(block.timestamp + 30 days);
        }
    }

    function _settleCycles(bytes32 id, uint256 amount, uint256 n) internal {
        for (uint256 i; i < n; ++i) {
            uint256 h = std.charge(id, amount);
            vm.warp(block.timestamp + window);
            std.finalize(h);
            vm.warp(block.timestamp + 30 days);
        }
    }

    function _solvent() internal view {
        assertGe(
            token.balanceOf(address(std)),
            std.totalHeld(address(token)) + std.accruedFees(address(token)),
            "solvent"
        );
    }

    // --- charge into escrow ---

    function test_chargeEscrowsAndLeavesMerchantUnpaid() public {
        bytes32 id = _mandate();
        uint256 holdId = std.charge(id, 30e6);

        assertEq(holdId, 1);
        assertEq(token.balanceOf(address(std)), 30e6);
        assertEq(token.balanceOf(merchant), 0, "merchant waits for the window");
        assertEq(std.totalHeld(address(token)), 30e6);

        Hold memory h = std.getHold(holdId);
        assertEq(h.mandateId, id);
        assertEq(h.payer, payer);
        assertEq(h.merchant, merchant);
        assertEq(h.amount, 30e6);
        assertEq(h.unlockAt, uint64(block.timestamp) + std.windowFor(merchant), "merchant's own tier");
        assertEq(uint8(h.status), uint8(HoldStatus.Held));

        assertEq(std.getMandate(id).chargeCount, 1);
        assertEq(std.getMandate(id).lastChargeAt, uint64(block.timestamp));
        _solvent();
    }

    function test_chargeIsPermissionless() public {
        bytes32 id = _mandate();
        vm.prank(makeAddr("anyone"));
        std.charge(id, 30e6);
        assertEq(std.totalHeld(address(token)), 30e6);
    }

    function test_repeatedCyclesSettleToMerchant() public {
        bytes32 id = _mandate();
        for (uint256 i; i < 4; ++i) {
            uint256 h = std.charge(id, 25e6);
            vm.warp(block.timestamp + window);
            std.finalize(h);
            vm.warp(block.timestamp + 30 days);
            _solvent();
        }
        assertEq(token.balanceOf(merchant), 100e6);
        assertEq(std.totalHeld(address(token)), 0);
    }

    function test_postpaidSettlesWithoutWindow() public {
        bytes32 id = _create(_terms(payer, address(token), ChargeKind.Postpaid, bytes32(uint256(7))));
        uint256 h = std.charge(id, 30e6);

        assertEq(std.getHold(h).unlockAt, uint64(block.timestamp));
        assertTrue(std.isHoldUnlocked(h));

        // Reported as a closed window rather than a low ceiling: a postpaid
        // charge is never reversible whatever the payer's standing.
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Escrow.WindowClosed.selector, uint64(block.timestamp)));
        std.reverse(h);

        std.finalize(h);
        assertEq(token.balanceOf(merchant), 30e6);
    }

    function test_safePayerFullCycle() public {
        MockERC1271Signer safe = new MockERC1271Signer(payer);
        _arm(address(safe), token);

        bytes32 id = _create(_terms(address(safe), address(token), ChargeKind.Prepaid, bytes32(uint256(8))));

        // Standing is per payer, so the Safe has to earn its own.
        while (std.reversalCeiling(address(safe)) < 30e6) {
            uint256 warm = std.charge(id, 30e6);
            vm.warp(block.timestamp + window);
            std.finalize(warm);
            vm.warp(block.timestamp + 30 days);
        }

        uint256 h = std.charge(id, 30e6);

        vm.prank(address(safe));
        std.reverse(h);
        assertEq(uint8(std.getHold(h).status), uint8(HoldStatus.Reversed));
    }

    // --- reversal ---

    function test_payerReversesAndMerchantGetsNothing() public {
        bytes32 id = _mandate();
        _buildStanding(id, 30e6);

        uint256 payerBefore = token.balanceOf(payer);
        uint256 merchantBefore = token.balanceOf(merchant);
        uint256 h = std.charge(id, 30e6);

        vm.prank(payer);
        std.reverse(h);

        assertEq(token.balanceOf(payer), payerBefore, "made whole");
        assertEq(token.balanceOf(merchant), merchantBefore, "merchant gained nothing");
        assertEq(std.totalHeld(address(token)), 0);
        _solvent();
    }

    /// A reversal undoes the money, not the record. The charge still counts
    /// against cadence, so a merchant cannot retry inside the interval.
    function test_reversalDoesNotResetCadence() public {
        bytes32 id = _mandate();
        _buildStanding(id, 30e6);

        uint32 chargesBefore = std.getMandate(id).chargeCount;
        uint256 h = std.charge(id, 30e6);
        vm.prank(payer);
        std.reverse(h);

        uint64 due = uint64(block.timestamp) + 30 days;
        assertEq(std.nextChargeAt(id), due);
        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.TooSoon.selector, due));
        std.charge(id, 30e6);
        assertEq(std.getMandate(id).chargeCount, chargesBefore + 1, "the reversed charge still counts");
    }

    /// Revoking mid-window must not strand or redirect funds already pulled:
    /// the hold settles on the terms in force when it was taken.
    function test_revokeMidWindowLeavesHoldIntact() public {
        bytes32 id = _mandate();
        uint256 h = std.charge(id, 30e6);

        vm.prank(payer);
        std.revokeMandate(id);

        assertFalse(std.isMandateLive(id));
        vm.warp(block.timestamp + window);
        std.finalize(h);
        assertEq(token.balanceOf(merchant), 30e6, "already-taken charge still settles");
        _solvent();
    }

    function test_revokeMidWindowStillAllowsReversal() public {
        bytes32 id = _mandate();
        _buildStanding(id, 30e6);

        uint256 h = std.charge(id, 30e6);

        vm.startPrank(payer);
        std.revokeMandate(id);
        std.reverse(h);
        vm.stopPrank();

        assertEq(uint8(std.getHold(h).status), uint8(HoldStatus.Reversed));
    }

    // --- reversal ceiling ---

    /// A fresh address has settled nothing, so its ceiling is zero and it can
    /// reverse nothing. This is what stops a first-ever reversal from being a
    /// free option.
    function test_noStandingMeansNoReversal() public {
        bytes32 id = _mandate();
        uint256 h = std.charge(id, 30e6);

        assertEq(std.reversalCeiling(payer), 0);
        assertFalse(std.isVested(payer));

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Standing.NotVested.selector, uint32(0), uint32(3)));
        std.reverse(h);
    }

    /// The case the ceiling alone does not cover. One clean settlement leaves
    /// a ceiling large enough to reverse the next charge outright, so without
    /// vesting a single payment would buy an immediate right.
    function test_oneLargeSettlementClearsCeilingButNotVesting() public {
        bytes32 id = _mandate();
        _settleCycles(id, 30e6, 1);

        assertEq(std.reversalCeiling(payer), 10e6, "ceiling would permit it");
        assertFalse(std.isVested(payer), "but no right exists yet");

        uint256 h = std.charge(id, 10e6);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Standing.NotVested.selector, uint32(1), uint32(3)));
        std.reverse(h);
    }

    function test_vestsAtExactlyThreeCleanCycles() public {
        bytes32 id = _mandate();

        for (uint32 i = 1; i <= 2; ++i) {
            _settleCycles(id, 30e6, 1);
            assertFalse(std.isVested(payer));
            assertEq(std.cyclesUntilVested(payer), 3 - i);
        }

        _settleCycles(id, 30e6, 1);
        assertTrue(std.isVested(payer));
        assertEq(std.cyclesUntilVested(payer), 0);

        uint256 h = std.charge(id, 30e6);
        vm.prank(payer);
        std.reverse(h);
        assertEq(uint8(std.getHold(h).status), uint8(HoldStatus.Reversed));
    }

    /// Only clean settlements vest the right. A reversal is not progress
    /// toward earning the ability to reverse again.
    function test_reversalsDoNotCountTowardVesting() public {
        bytes32 id = _mandate();
        _settleCycles(id, 30e6, 3);
        assertTrue(std.isVested(payer));

        uint256 h = std.charge(id, 30e6);
        vm.prank(payer);
        std.reverse(h);

        assertEq(std.cleanSettlementsOf(payer), 3, "still three, the reversal added none");
    }

    function test_vestingIsPerPayer() public {
        bytes32 id = _mandate();
        _settleCycles(id, 30e6, 3);

        assertTrue(std.isVested(payer));
        assertFalse(std.isVested(merchant));
        assertEq(std.cyclesUntilVested(makeAddr("stranger")), 3);
    }

    function test_ceilingIsAThirdOfCleanSettled() public {
        bytes32 id = _mandate();
        uint256 h = std.charge(id, 30e6);
        vm.warp(block.timestamp + window);
        std.finalize(h);

        assertEq(std.standingOf(payer).cumulativeCleanSettled, 30e6);
        assertEq(std.reversalCeiling(payer), 10e6);
    }

    function test_reversalAtExactlyTheCeilingIsAllowed() public {
        bytes32 id = _mandate();
        _buildStanding(id, 30e6);
        assertEq(std.reversalCeiling(payer), 30e6);

        uint256 h = std.charge(id, 30e6);
        vm.prank(payer);
        std.reverse(h);
        assertEq(uint8(std.getHold(h).status), uint8(HoldStatus.Reversed));
    }

    function test_oneWeiAboveTheCeilingIsRefused() public {
        bytes32 id = _mandate();
        _settleCycles(id, 10e6, 3); // vested, 30e6 settled, ceiling 10e6

        uint256 ceiling = std.reversalCeiling(payer);
        assertEq(ceiling, 10e6);
        assertTrue(std.isVested(payer));

        uint256 above = std.charge(id, ceiling + 1);
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Standing.AboveReversalCeiling.selector, ceiling));
        std.reverse(above);

        vm.warp(block.timestamp + 30 days);
        uint256 exact = std.charge(id, ceiling);
        vm.prank(payer);
        std.reverse(exact);
        assertEq(uint8(std.getHold(exact).status), uint8(HoldStatus.Reversed));
    }

    /// The ceiling tracks value, not the number of settlements. Thirty small
    /// clean cycles unlock exactly as much as one large one of the same total,
    /// so padding a history with cheap payments buys nothing.
    function test_ceilingTracksValueNotCount() public {
        bytes32 many = _mandate();
        Mandate memory m = _terms(payer, address(token), ChargeKind.Prepaid, bytes32(uint256(20)));
        m.minInterval = 1;
        bytes32 small = _create(m);

        for (uint256 i; i < 30; ++i) {
            uint256 h = std.charge(small, 1e6);
            vm.warp(block.timestamp + window);
            std.finalize(h);
            vm.warp(block.timestamp + 1);
        }
        uint256 ceilingFromMany = std.reversalCeiling(payer);
        assertEq(ceilingFromMany, 10e6, "30e6 settled in small pieces");
        assertEq(std.standingOf(payer).cleanSettlements, 30);

        uint256 big = std.charge(many, 30e6);
        vm.warp(block.timestamp + window);
        std.finalize(big);
        assertEq(std.reversalCeiling(payer), 20e6, "one 30e6 cycle added the same value");
    }

    function test_ceilingGrowsWithHistory() public {
        bytes32 id = _mandate();
        uint256 last;
        for (uint256 i; i < 4; ++i) {
            uint256 h = std.charge(id, 30e6);
            vm.warp(block.timestamp + window);
            std.finalize(h);
            uint256 now_ = std.reversalCeiling(payer);
            assertGt(now_, last, "each clean cycle raises it");
            last = now_;
            vm.warp(block.timestamp + 30 days);
        }
        assertEq(last, 40e6);
    }

    /// A reversal earns no standing, so it cannot fund the next one.
    function test_reversalDoesNotRaiseTheCeiling() public {
        bytes32 id = _mandate();
        _buildStanding(id, 30e6);
        uint256 ceilingBefore = std.reversalCeiling(payer);

        uint256 h = std.charge(id, 30e6);
        vm.prank(payer);
        std.reverse(h);

        assertEq(std.reversalCeiling(payer), ceilingBefore, "unchanged");
    }

    // --- abuse trigger and suspension ---

    /// Reversals piled on one merchant never trip the trigger. That pattern is
    /// evidence about the merchant, not the payer, so punishing the payer
    /// would penalise the customer of a broken integration.
    function test_concentratedReversalsNeverSuspend() public {
        bytes32 id = _mandate();
        _settleCycles(id, 30e6, 3);

        for (uint256 i; i < 5; ++i) {
            uint256 h = std.charge(id, 30e6);
            vm.prank(payer);
            std.reverse(h);
            vm.warp(block.timestamp + 30 days);
        }

        assertEq(std.standingOf(payer).reversals, 5);
        assertEq(std.standingOf(payer).distinctMerchantsReversed, 1);
        assertFalse(std.isAbusive(payer), "one counterparty is not a pattern");
        assertFalse(std.isSuspended(payer));
    }

    /// The same rate spread across unrelated merchants is the payer's habit,
    /// and it suspends the right.
    function test_dispersedReversalsSuspend() public {
        bytes32 a = _mandate();
        Mandate memory mb =
            _termsFor(payer, merchantB, address(token), ChargeKind.Prepaid, bytes32(uint256(31)));
        mb.minInterval = 1;
        Mandate memory mc =
            _termsFor(payer, merchantC, address(token), ChargeKind.Prepaid, bytes32(uint256(32)));
        mc.minInterval = 1;
        bytes32 b = _create(mb);
        bytes32 c = _create(mc);

        _settleCycles(a, 30e6, 3);
        assertTrue(std.isVested(payer));

        _reverseOne(a);
        assertFalse(std.isAbusive(payer), "sample too small");

        _reverseOne(b);
        assertFalse(std.isAbusive(payer), "only two merchants");

        _reverseOne(c);
        assertTrue(std.isAbusive(payer), "three merchants, rate above threshold");
        assertTrue(std.isSuspended(payer));
        assertEq(std.cyclesUntilRestored(payer), 3);
    }

    function _reverseOne(bytes32 id) internal {
        uint256 h = std.charge(id, 30e6);
        vm.prank(payer);
        std.reverse(h);
        vm.warp(block.timestamp + 30 days);
    }

    function test_suspensionBlocksFurtherReversals() public {
        _suspendPayer();

        bytes32 id = _mandate();
        uint256 h = std.charge(id, 30e6);
        assertEq(uint8(std.reversalBlocker(h, payer)), uint8(ReversalBlock.Suspended));

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Standing.ReversalSuspended.selector, uint32(3)));
        std.reverse(h);
    }

    /// Served in clean settlements, so waiting is not a way out.
    function test_suspensionCannotBeWaitedOut() public {
        _suspendPayer();

        vm.warp(block.timestamp + 3650 days);
        assertTrue(std.isSuspended(payer), "time alone changes nothing");
    }

    function test_suspensionLiftsAfterThreeCleanCycles() public {
        _suspendPayer();
        bytes32 id = _mandate();

        _settleCycles(id, 30e6, 2);
        assertTrue(std.isSuspended(payer));
        assertEq(std.cyclesUntilRestored(payer), 1);

        _settleCycles(id, 30e6, 1);
        assertFalse(std.isSuspended(payer), "earned back by paying cleanly");
        assertEq(std.cyclesUntilRestored(payer), 0);

        uint256 h = std.charge(id, 30e6);
        vm.prank(payer);
        std.reverse(h);
        assertEq(uint8(std.getHold(h).status), uint8(HoldStatus.Reversed));
    }

    /// Drives a payer into suspension through three dispersed reversals.
    function _suspendPayer() internal {
        bytes32 a = _mandate();
        Mandate memory mb =
            _termsFor(payer, merchantB, address(token), ChargeKind.Prepaid, bytes32(uint256(41)));
        mb.minInterval = 1;
        Mandate memory mc =
            _termsFor(payer, merchantC, address(token), ChargeKind.Prepaid, bytes32(uint256(42)));
        mc.minInterval = 1;
        bytes32 b = _create(mb);
        bytes32 c = _create(mc);

        _settleCycles(a, 30e6, 3);
        _reverseOne(a);
        _reverseOne(b);
        _reverseOne(c);
        assertTrue(std.isSuspended(payer), "setup should have suspended");
    }

    // --- reversal probe ---

    function test_blockerReportsEachReasonInOrder() public {
        bytes32 id = _mandate();
        uint256 h = std.charge(id, 30e6);

        assertEq(uint8(std.reversalBlocker(h, merchant)), uint8(ReversalBlock.NotPayer));
        assertEq(uint8(std.reversalBlocker(h, payer)), uint8(ReversalBlock.NotVested));
        assertEq(uint8(std.reversalBlocker(999, payer)), uint8(ReversalBlock.HoldNotOpen));

        vm.warp(block.timestamp + window);
        assertEq(uint8(std.reversalBlocker(h, payer)), uint8(ReversalBlock.WindowClosed));
        std.finalize(h);
        assertEq(uint8(std.reversalBlocker(h, payer)), uint8(ReversalBlock.HoldNotOpen));
    }

    function test_blockerReportsAboveCeiling() public {
        bytes32 id = _mandate();
        _settleCycles(id, 10e6, 3);

        uint256 h = std.charge(id, 30e6);
        assertEq(uint8(std.reversalBlocker(h, payer)), uint8(ReversalBlock.AboveCeiling));
        assertFalse(std.canReverse(h, payer));
    }

    function test_blockerReportsNoneWhenAllowed() public {
        bytes32 id = _mandate();
        _buildStanding(id, 30e6);

        uint256 h = std.charge(id, 30e6);
        assertEq(uint8(std.reversalBlocker(h, payer)), uint8(ReversalBlock.None));
        assertTrue(std.canReverse(h, payer));
    }

    /// The probe and the guard must never disagree, or the frontend will offer
    /// a reversal the transaction refuses.
    function testFuzz_probeAgreesWithGuard(uint256 amountSeed, uint64 skip, bool warmed) public {
        bytes32 id = _mandate();
        if (warmed) _settleCycles(id, 30e6, 3);

        uint256 amount = bound(amountSeed, 1, 30e6);
        uint256 h = std.charge(id, amount);
        vm.warp(block.timestamp + bound(skip, 0, 10 days));

        bool allowed = std.canReverse(h, payer);
        vm.prank(payer);
        if (allowed) {
            std.reverse(h);
        } else {
            vm.expectRevert();
            std.reverse(h);
        }
    }

    // --- revert branches ---

    function test_revertsAboveCap() public {
        bytes32 id = _mandate();
        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.AmountExceedsCap.selector, 30e6));
        std.charge(id, 30e6 + 1);
    }

    function test_revertsOnZeroAmount() public {
        bytes32 id = _mandate();
        vm.expectRevert(MandateRegistry.ZeroAmount.selector);
        std.charge(id, 0);
    }

    function test_revertsTooSoon() public {
        bytes32 id = _mandate();
        std.charge(id, 10e6);
        uint64 due = uint64(block.timestamp) + 30 days;

        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.TooSoon.selector, due));
        std.charge(id, 10e6);
    }

    function test_revertsWhenRevoked() public {
        bytes32 id = _mandate();
        vm.prank(payer);
        std.revokeMandate(id);

        vm.expectRevert(MandateRegistry.NotLive.selector);
        std.charge(id, 10e6);
    }

    function test_revertsAfterRevokeAll() public {
        bytes32 id = _mandate();
        vm.prank(payer);
        std.revokeAll();

        vm.expectRevert(MandateRegistry.NotLive.selector);
        std.charge(id, 10e6);
    }

    function test_revertsAfterMandateExpiry() public {
        Mandate memory m = _terms(payer, address(token), ChargeKind.Prepaid, bytes32(uint256(9)));
        m.expiresAt = uint64(block.timestamp + 10 days);
        bytes32 id = _create(m);

        vm.warp(uint256(m.expiresAt));
        vm.expectRevert(MandateRegistry.NotLive.selector);
        std.charge(id, 10e6);
    }

    function test_revertsOnChargeLimit() public {
        Mandate memory m = _terms(payer, address(token), ChargeKind.Prepaid, bytes32(uint256(10)));
        m.maxCharges = 1;
        bytes32 id = _create(m);

        std.charge(id, 10e6);
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.ChargeLimitReached.selector, uint32(1)));
        std.charge(id, 10e6);
    }

    function test_revertsOnUnknownMandate() public {
        vm.expectRevert(MandateRegistry.NotLive.selector);
        std.charge(keccak256("absent"), 10e6);
    }

    /// The Permit2 expiry is a kill switch Standing cannot see from its own
    /// state, which is why the dashboard must read the allowance separately.
    function test_permit2ExpiryStopsChargeWhileMandateLooksChargeable() public {
        bytes32 id = _mandate();
        vm.warp(uint256(permitExpiry) + 1);

        assertTrue(std.isChargeable(id, 10e6), "mandate side is happy");
        vm.expectRevert(MockPermit2.AllowanceExpired.selector);
        std.charge(id, 10e6);
    }

    function test_revertsOnFeeOnTransferToken() public {
        MockERC20 feeToken = new MockERC20(100);
        _arm(payer, feeToken);

        bytes32 id = _create(_terms(payer, address(feeToken), ChargeKind.Prepaid, bytes32(uint256(11))));
        vm.expectRevert(Permit2Puller.InexactTransfer.selector);
        std.charge(id, 30e6);
    }

    function test_failedPullLeavesNoTrace() public {
        bytes32 id = _mandate();
        vm.prank(payer);
        permit2.approve(address(token), address(std), 1e6, permitExpiry);

        vm.expectRevert(MockPermit2.InsufficientAllowance.selector);
        std.charge(id, 30e6);

        assertEq(std.getMandate(id).chargeCount, 0);
        assertEq(std.getMandate(id).lastChargeAt, 0);
        assertEq(std.nextHoldId(), 1, "no hold booked");
        assertEq(std.totalHeld(address(token)), 0);
    }

    // --- reentrancy ---

    function _hostile() internal returns (ReenteringToken hostile) {
        hostile = new ReenteringToken();
        hostile.mint(payer, 100_000e6);
        vm.startPrank(payer);
        hostile.approve(address(permit2), type(uint256).max);
        permit2.approve(address(hostile), address(std), 50_000e6, permitExpiry);
        vm.stopPrank();
    }

    /// Recording before the pull is what stops a hostile mandate token from
    /// clearing the cadence check a second time during its own transferFrom.
    function test_reentrantChargeBlockedByCadence() public {
        ReenteringToken hostile = _hostile();
        bytes32 id = _create(_terms(payer, address(hostile), ChargeKind.Prepaid, bytes32(uint256(12))));
        hostile.arm(IChargeable(address(std)), id, 30e6, false);

        vm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.TooSoon.selector, uint64(block.timestamp) + 30 days)
        );
        std.charge(id, 30e6);

        assertEq(std.getMandate(id).chargeCount, 0);
        assertEq(hostile.balanceOf(address(std)), 0);
        assertEq(std.nextHoldId(), 1);
    }

    /// The same attack against record-after-pull. The cadence guard no longer
    /// catches it, but the exact-transfer guard does, because the reentrant
    /// pull inflates the balance delta the outer pull measures. Two
    /// independent layers.
    function test_reentrancyCaughtByExactTransferWhenRecordedLate() public {
        UnsafeOrderingHarness unsafe = new UnsafeOrderingHarness(address(permit2), owner);

        ReenteringToken hostile = new ReenteringToken();
        hostile.mint(payer, 100_000e6);
        vm.startPrank(payer);
        hostile.approve(address(permit2), type(uint256).max);
        permit2.approve(address(hostile), address(unsafe), 50_000e6, permitExpiry);
        vm.stopPrank();

        Mandate memory m = _terms(payer, address(hostile), ChargeKind.Prepaid, bytes32(uint256(13)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, unsafe.mandateDigest(m));
        bytes32 id = unsafe.createMandate(m, abi.encodePacked(r, s, v));
        hostile.arm(IChargeable(address(unsafe)), id, 30e6, true);

        vm.expectRevert(Permit2Puller.InexactTransfer.selector);
        unsafe.chargeRecordLast(id, 30e6);

        assertEq(hostile.balanceOf(address(unsafe)), 0);
        assertEq(unsafe.getMandate(id).chargeCount, 0);
    }

    // --- fuzz ---

    function testFuzz_chargeRespectsCap(uint256 amount) public {
        bytes32 id = _mandate();
        amount = bound(amount, 1, 100e6);

        if (amount <= 30e6) {
            std.charge(id, amount);
            assertEq(std.totalHeld(address(token)), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(MandateRegistry.AmountExceedsCap.selector, 30e6));
            std.charge(id, amount);
        }
        _solvent();
    }

    function testFuzz_solventAcrossMixedOutcomes(uint16 bps, uint96 amount, uint8 pattern) public {
        uint16 rate = uint16(bound(bps, 0, std.MAX_FEE_BPS()));
        vm.prank(owner);
        std.setFeeBps(rate);

        bytes32 id = _mandate();
        uint256 each = bound(amount, 1, 30e6);
        _buildStanding(id, each);

        for (uint256 i; i < 6; ++i) {
            uint256 h = std.charge(id, each);
            _solvent();

            if ((pattern >> (i % 8)) & 1 == 1) {
                vm.prank(payer);
                std.reverse(h);
            } else {
                vm.warp(block.timestamp + window);
                std.finalize(h);
            }
            _solvent();
            vm.warp(block.timestamp + 30 days);
        }
        assertEq(std.totalHeld(address(token)), 0);
    }
}
