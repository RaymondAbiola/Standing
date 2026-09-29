// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {PayerStanding} from "../src/base/StandingBook.sol";
import {StandingBookHarness} from "./harness/StandingBookHarness.sol";

contract StandingBookTest is Test {
    event StandingSettled(address indexed payer, uint256 amount, uint256 cumulativeCleanSettled);
    event StandingReversed(address indexed payer, address indexed merchant, uint32 distinctMerchants);

    StandingBookHarness internal book;

    address internal payer = makeAddr("payer");
    address internal other = makeAddr("other");
    address internal mA = makeAddr("mA");
    address internal mB = makeAddr("mB");
    address internal mC = makeAddr("mC");
    address internal mD = makeAddr("mD");

    function setUp() public {
        book = new StandingBookHarness();
        vm.warp(1_000_000);
    }

    function _settle(uint256 n, uint256 amount) internal {
        for (uint256 i; i < n; ++i) {
            book.settle(payer, amount);
        }
    }

    // --- counters ---

    function test_settlementsAccrueAndEmit() public {
        vm.expectEmit(true, false, false, true);
        emit StandingSettled(payer, 30e6, 30e6);
        book.settle(payer, 30e6);
        book.settle(payer, 20e6);

        PayerStanding memory s = book.standingOf(payer);
        assertEq(s.cumulativeCleanSettled, 50e6);
        assertEq(s.cleanSettlements, 2);
        assertEq(s.reversals, 0);
        assertEq(book.sampleSize(payer), 2);
        assertEq(book.reversalsInWindow(payer), 0);
    }

    function test_reversalsAccrueAndEmit() public {
        vm.expectEmit(true, true, false, true);
        emit StandingReversed(payer, mA, 1);
        book.reverseAgainst(payer, mA);

        PayerStanding memory s = book.standingOf(payer);
        assertEq(s.reversals, 1);
        assertEq(s.cleanSettlements, 0);
        assertEq(s.cumulativeCleanSettled, 0, "a reversal earns no standing");
        assertEq(book.reversalsInWindow(payer), 1);
    }

    function test_standingIsPerPayer() public {
        book.settle(payer, 30e6);
        book.reverseAgainst(payer, mA);

        assertEq(book.standingOf(other).cumulativeCleanSettled, 0);
        assertEq(book.standingOf(other).reversals, 0);
        assertFalse(book.isSuspended(other));
        assertFalse(book.hasReversedAgainst(other, mA));
    }

    // --- rolling window ---

    /// An old bad run has to age out, or a payer could never recover.
    function test_windowForgets() public {
        book.reverseAgainst(payer, mA);
        book.reverseAgainst(payer, mB);
        book.reverseAgainst(payer, mC);
        assertEq(book.reversalsInWindow(payer), 3);

        _settle(10, 1e6);
        assertEq(book.reversalsInWindow(payer), 0, "aged out");
        assertEq(book.standingOf(payer).reversals, 3, "lifetime count kept");
    }

    function test_windowNeverExceedsTen() public {
        for (uint256 i; i < 20; ++i) {
            book.reverseAgainst(payer, mA);
        }
        assertEq(book.reversalsInWindow(payer), 10);
        assertEq(book.sampleSize(payer), 10);
        assertEq(book.standingOf(payer).reversals, 20);
    }

    function test_bitfieldSaturatesAtThirtyTwo() public {
        _settle(40, 1e6);
        assertEq(book.standingOf(payer).recentCount, 32);
        assertEq(book.sampleSize(payer), 10);
    }

    function testFuzz_windowMatchesBruteForce(bool[24] memory outcomes) public {
        for (uint256 i; i < outcomes.length; ++i) {
            if (outcomes[i]) book.reverseAgainst(payer, mA);
            else book.settle(payer, 1e6);
        }

        uint8 expected;
        for (uint256 i; i < 10; ++i) {
            if (outcomes[outcomes.length - 1 - i]) expected += 1;
        }
        assertEq(book.reversalsInWindow(payer), expected);
    }

    // --- dispersion ---

    function test_dispersionCountsMerchantsNotReversals() public {
        for (uint256 i; i < 5; ++i) {
            book.reverseAgainst(payer, mA);
        }
        assertEq(book.standingOf(payer).reversals, 5);
        assertEq(book.standingOf(payer).distinctMerchantsReversed, 1);

        book.reverseAgainst(payer, mB);
        book.reverseAgainst(payer, mC);
        assertEq(book.standingOf(payer).distinctMerchantsReversed, 3);
        assertTrue(book.hasReversedAgainst(payer, mB));
        assertFalse(book.hasReversedAgainst(payer, mD));
    }

    // --- vesting ---

    function test_vestsAtThreeCleanSettlements() public {
        assertFalse(book.isVested(payer));
        assertEq(book.cyclesUntilVested(payer), 3);

        book.settle(payer, 1e6);
        assertEq(book.cyclesUntilVested(payer), 2);
        book.settle(payer, 1e6);
        assertEq(book.cyclesUntilVested(payer), 1);
        assertFalse(book.isVested(payer));

        book.settle(payer, 1e6);
        assertTrue(book.isVested(payer));
        assertEq(book.cyclesUntilVested(payer), 0);
    }

    function test_reversalsDoNotVest() public {
        for (uint256 i; i < 10; ++i) {
            book.reverseAgainst(payer, mA);
        }
        assertFalse(book.isVested(payer));
        assertEq(book.cyclesUntilVested(payer), 3);
    }

    // --- ceiling ---

    function test_ceilingIsAThirdOfSettled() public {
        book.settle(payer, 90e6);
        assertEq(book.reversalCeiling(payer), 30e6);
        book.settle(payer, 30e6);
        assertEq(book.reversalCeiling(payer), 40e6);
    }

    function test_ceilingIgnoresCount() public {
        _settle(30, 1e6);
        assertEq(book.reversalCeiling(payer), 10e6, "30e6 in small pieces");

        book.settle(other, 30e6);
        assertEq(book.reversalCeiling(other), 10e6, "same total, one piece, same ceiling");
    }

    function test_ceilingRoundsDown() public {
        book.settle(payer, 5);
        assertEq(book.reversalCeiling(payer), 1, "5 / 3");
        book.settle(payer, 1);
        assertEq(book.reversalCeiling(payer), 2, "6 / 3");
    }

    // --- abuse trigger ---

    /// Reversals against a single merchant are evidence about that merchant,
    /// so no rate against one counterparty can trip the trigger.
    function test_concentratedNeverAbusive() public {
        _settle(3, 30e6);
        for (uint256 i; i < 20; ++i) {
            book.reverseAgainst(payer, mA);
        }
        assertEq(book.reversalsInWindow(payer), 10, "rate is as high as it goes");
        assertEq(book.standingOf(payer).distinctMerchantsReversed, 1);
        assertFalse(book.isAbusive(payer));
    }

    function test_needsMinimumSample() public {
        book.reverseAgainst(payer, mA);
        book.reverseAgainst(payer, mB);
        book.reverseAgainst(payer, mC);
        book.settle(payer, 1e6);

        assertEq(book.sampleSize(payer), 4);
        assertEq(book.standingOf(payer).distinctMerchantsReversed, 3);
        assertFalse(book.isAbusive(payer), "four outcomes is not a pattern");

        book.settle(payer, 1e6);
        assertEq(book.sampleSize(payer), 5);
        assertTrue(book.isAbusive(payer));
    }

    /// The threshold is strictly above 20 percent, so exactly two in ten is
    /// tolerated. A payer who reverses one charge in five is not an abuser.
    function test_exactlyTwentyPercentIsTolerated() public {
        // Eleven outcomes: three reversals then eight settlements, so the
        // ten-outcome window holds two of the three.
        book.reverseAgainst(payer, mA);
        book.reverseAgainst(payer, mB);
        book.reverseAgainst(payer, mC);
        _settle(8, 1e6);

        assertEq(book.sampleSize(payer), 10);
        assertEq(book.reversalsInWindow(payer), 2, "oldest aged out");
        assertEq(book.standingOf(payer).distinctMerchantsReversed, 3);
        assertFalse(book.isAbusive(payer), "exactly at the threshold, not above it");
    }

    /// Three in ten is above the threshold and trips.
    ///
    /// A separate payer rather than one more reversal on the payer above,
    /// because each new outcome also pushes one out of the window: with eight
    /// settlements in the way the count cannot climb past two.
    function test_threeInTenIsAbusive() public {
        book.reverseAgainst(other, mA);
        book.reverseAgainst(other, mB);
        book.reverseAgainst(other, mC);
        for (uint256 i; i < 7; ++i) {
            book.settle(other, 1e6);
        }

        assertEq(book.sampleSize(other), 10);
        assertEq(book.reversalsInWindow(other), 3);
        assertEq(book.standingOf(other).distinctMerchantsReversed, 3);
        assertTrue(book.isAbusive(other));
    }

    function test_dispersionBelowThresholdIsNotAbusive() public {
        book.reverseAgainst(payer, mA);
        book.reverseAgainst(payer, mA);
        book.reverseAgainst(payer, mB);
        _settle(2, 1e6);

        assertEq(book.sampleSize(payer), 5);
        assertEq(book.reversalsInWindow(payer), 3);
        assertEq(book.standingOf(payer).distinctMerchantsReversed, 2);
        assertFalse(book.isAbusive(payer), "two merchants is not dispersed");
    }

    /// Clean history pushes an abusive pattern out of the window, so the
    /// judgement is about recent behaviour rather than a permanent mark.
    function test_abusiveStateClearsWithCleanHistory() public {
        book.reverseAgainst(payer, mA);
        book.reverseAgainst(payer, mB);
        book.reverseAgainst(payer, mC);
        _settle(2, 1e6);
        assertTrue(book.isAbusive(payer));

        _settle(10, 1e6);
        assertFalse(book.isAbusive(payer), "window is clean again");
        assertEq(book.standingOf(payer).distinctMerchantsReversed, 3, "dispersion is lifetime");
    }

    // --- suspension ---

    function test_suspensionServedInCleanSettlements() public {
        _settle(4, 1e6);
        assertEq(book.suspend(payer, 3), 7, "restores at seven clean");
        assertTrue(book.isSuspended(payer));
        assertEq(book.cyclesUntilRestored(payer), 3);

        vm.warp(block.timestamp + 3650 days);
        assertTrue(book.isSuspended(payer), "time is not progress");

        book.settle(payer, 1e6);
        assertEq(book.cyclesUntilRestored(payer), 2);
        _settle(2, 1e6);
        assertFalse(book.isSuspended(payer));
        assertEq(book.cyclesUntilRestored(payer), 0);
    }

    function test_reversalsAreNotProgressTowardRestoration() public {
        book.suspend(payer, 2);
        book.reverseAgainst(payer, mA);
        book.reverseAgainst(payer, mB);

        assertTrue(book.isSuspended(payer));
        assertEq(book.cyclesUntilRestored(payer), 2, "unmoved");
    }

    /// Re-suspending while already suspended extends from where the payer is
    /// now, so an abuser cannot shorten a suspension by tripping it again.
    function test_resuspensionExtendsFromCurrentPosition() public {
        _settle(2, 1e6);
        book.suspend(payer, 3);
        assertEq(book.cyclesUntilRestored(payer), 3);

        book.settle(payer, 1e6);
        assertEq(book.cyclesUntilRestored(payer), 2);

        book.suspend(payer, 3);
        assertEq(book.cyclesUntilRestored(payer), 3, "reset, not shortened");
    }

    function test_neverSuspendedReportsZeroOwed() public view {
        assertFalse(book.isSuspended(payer));
        assertEq(book.cyclesUntilRestored(payer), 0);
    }

    // --- full lifecycle ---

    /// Cold address through vesting, into abuse, through suspension, and back
    /// out the far side.
    function test_fullLifecycle() public {
        assertFalse(book.isVested(payer));
        assertEq(book.reversalCeiling(payer), 0);

        _settle(3, 30e6);
        assertTrue(book.isVested(payer));
        assertEq(book.reversalCeiling(payer), 30e6);
        assertFalse(book.isAbusive(payer));

        book.reverseAgainst(payer, mA);
        book.reverseAgainst(payer, mB);
        assertFalse(book.isAbusive(payer), "two merchants");

        book.reverseAgainst(payer, mC);
        assertTrue(book.isAbusive(payer));

        book.suspend(payer, 3);
        assertTrue(book.isSuspended(payer));

        _settle(3, 30e6);
        assertFalse(book.isSuspended(payer));
        assertTrue(book.isVested(payer));
        assertEq(book.reversalCeiling(payer), 60e6, "180e6 settled");
        assertEq(book.standingOf(payer).cleanSettlements, 6);
        assertEq(book.standingOf(payer).reversals, 3);
    }

    function testFuzz_ceilingNeverExceedsSettled(uint128[6] memory amounts) public {
        uint256 total;
        for (uint256 i; i < amounts.length; ++i) {
            book.settle(payer, amounts[i]);
            total += amounts[i];
        }
        assertEq(book.standingOf(payer).cumulativeCleanSettled, total);
        assertLe(book.reversalCeiling(payer), total / 3);
    }
}
