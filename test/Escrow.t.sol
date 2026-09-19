// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Test} from "forge-std/Test.sol";

import {Escrow, Hold, HoldStatus} from "../src/base/Escrow.sol";
import {EscrowHarness} from "./harness/EscrowHarness.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract EscrowTest is Test {
    event HoldOpened(
        uint256 indexed holdId,
        bytes32 indexed mandateId,
        address indexed merchant,
        address payer,
        address token,
        uint256 amount,
        uint64 unlockAt
    );
    event HoldFinalized(
        uint256 indexed holdId, address indexed merchant, address token, uint256 paid, uint256 fee
    );
    event HoldReversed(uint256 indexed holdId, address indexed payer, address token, uint256 amount);

    EscrowHarness internal esc;
    MockERC20 internal tok;
    MockERC20 internal other;

    address internal owner = makeAddr("owner");
    address internal payer = makeAddr("payer");
    address internal merchant = makeAddr("merchant");
    address internal treasury = makeAddr("treasury");

    bytes32 internal constant MID = keccak256("mandate");

    function setUp() public {
        vm.warp(1_000_000);
        esc = new EscrowHarness(owner);
        tok = new MockERC20(0);
        other = new MockERC20(0);
    }

    /// Books a hold with the funds already present, which is the invariant
    /// `_openHold` assumes.
    function _funded(uint256 amount, uint64 window) internal returns (uint256 holdId) {
        tok.mint(address(esc), amount);
        holdId = esc.open(MID, payer, merchant, address(tok), amount, window);
    }

    function _solvent() internal view {
        assertGe(tok.balanceOf(address(esc)), esc.totalHeld(address(tok)) + esc.accruedFees(address(tok)));
    }

    // --- opening holds ---

    function test_idsStartAtOne() public {
        assertEq(esc.nextHoldId(), 1);
        assertEq(_funded(30e6, 3 days), 1);
        assertEq(_funded(10e6, 3 days), 2);
        assertEq(esc.nextHoldId(), 3);
    }

    function test_openStoresFieldsAndEmits() public {
        tok.mint(address(esc), 30e6);
        uint64 unlockAt = uint64(block.timestamp) + 3 days;

        vm.expectEmit(true, true, true, true);
        emit HoldOpened(1, MID, merchant, payer, address(tok), 30e6, unlockAt);
        uint256 holdId = esc.open(MID, payer, merchant, address(tok), 30e6, 3 days);

        Hold memory h = esc.getHold(holdId);
        assertEq(h.mandateId, MID);
        assertEq(h.payer, payer);
        assertEq(h.merchant, merchant);
        assertEq(h.token, address(tok));
        assertEq(h.amount, 30e6);
        assertEq(h.unlockAt, unlockAt);
        assertEq(h.feeBps, 0);
        assertEq(uint8(h.status), uint8(HoldStatus.Held));
    }

    function test_totalHeldIsPerToken() public {
        _funded(30e6, 1 days);
        other.mint(address(esc), 5e6);
        esc.open(MID, payer, merchant, address(other), 5e6, 1 days);

        assertEq(esc.totalHeld(address(tok)), 30e6);
        assertEq(esc.totalHeld(address(other)), 5e6);
    }

    function test_windowCappedAtMax() public {
        uint64 maxWindow = esc.MAX_WINDOW();
        tok.mint(address(esc), 2e6);
        esc.open(MID, payer, merchant, address(tok), 1e6, maxWindow);

        vm.expectRevert(abi.encodeWithSelector(Escrow.WindowTooLong.selector, maxWindow));
        esc.open(MID, payer, merchant, address(tok), 1e6, maxWindow + 1);
    }

    // --- unlock timing ---

    function test_unlockBoundary() public {
        uint256 h = _funded(30e6, 3 days);
        assertFalse(esc.isHoldUnlocked(h));
        assertEq(esc.timeUntilUnlock(h), 3 days);

        vm.warp(block.timestamp + 3 days - 1);
        assertFalse(esc.isHoldUnlocked(h));
        assertEq(esc.timeUntilUnlock(h), 1);

        vm.warp(block.timestamp + 1);
        assertTrue(esc.isHoldUnlocked(h));
        assertEq(esc.timeUntilUnlock(h), 0);
    }

    function test_zeroWindowUnlocksImmediately() public {
        uint256 h = _funded(30e6, 0);
        assertTrue(esc.isHoldUnlocked(h));
        assertEq(esc.timeUntilUnlock(h), 0);
    }

    function test_unknownHoldIsInert() public {
        assertFalse(esc.isHoldUnlocked(999));
        assertEq(esc.timeUntilUnlock(999), 0);
        assertEq(esc.getHold(999).amount, 0);

        vm.expectRevert(Escrow.UnknownHold.selector);
        esc.finalize(999);
        vm.prank(payer);
        vm.expectRevert(Escrow.UnknownHold.selector);
        esc.reverse(999);
    }

    // --- finalize ---

    function test_finalizePaysMerchantAfterWindow() public {
        uint256 h = _funded(30e6, 3 days);
        vm.warp(block.timestamp + 3 days);

        vm.expectEmit(true, true, false, true);
        emit HoldFinalized(h, merchant, address(tok), 30e6, 0);
        esc.finalize(h);

        assertEq(tok.balanceOf(merchant), 30e6);
        assertEq(esc.totalHeld(address(tok)), 0);
        assertEq(uint8(esc.getHold(h).status), uint8(HoldStatus.Finalized));
        _solvent();
    }

    function test_finalizeIsPermissionless() public {
        uint256 h = _funded(30e6, 0);
        vm.prank(makeAddr("stranger"));
        esc.finalize(h);
        assertEq(tok.balanceOf(merchant), 30e6);
    }

    function test_finalizeRevertsWhileLocked() public {
        uint256 h = _funded(30e6, 3 days);
        uint64 unlockAt = esc.getHold(h).unlockAt;

        vm.expectRevert(abi.encodeWithSelector(Escrow.StillLocked.selector, unlockAt));
        esc.finalize(h);

        vm.warp(unlockAt - 1);
        vm.expectRevert(abi.encodeWithSelector(Escrow.StillLocked.selector, unlockAt));
        esc.finalize(h);
    }

    function test_noDoubleFinalize() public {
        uint256 h = _funded(30e6, 0);
        esc.finalize(h);

        vm.expectRevert(Escrow.HoldNotOpen.selector);
        esc.finalize(h);
        assertEq(tok.balanceOf(merchant), 30e6, "paid exactly once");
    }

    // --- reverse ---

    function test_reverseReturnsFundsToPayer() public {
        uint256 h = _funded(30e6, 3 days);

        vm.expectEmit(true, true, false, true);
        emit HoldReversed(h, payer, address(tok), 30e6);
        vm.prank(payer);
        esc.reverse(h);

        assertEq(tok.balanceOf(payer), 30e6);
        assertEq(tok.balanceOf(merchant), 0);
        assertEq(esc.totalHeld(address(tok)), 0);
        assertEq(uint8(esc.getHold(h).status), uint8(HoldStatus.Reversed));
        _solvent();
    }

    function test_reverseIsPayerOnly() public {
        uint256 h = _funded(30e6, 3 days);

        vm.prank(merchant);
        vm.expectRevert(Escrow.NotHoldPayer.selector);
        esc.reverse(h);

        vm.prank(owner);
        vm.expectRevert(Escrow.NotHoldPayer.selector);
        esc.reverse(h);
    }

    function test_noReverseAfterWindow() public {
        uint256 h = _funded(30e6, 3 days);
        uint64 unlockAt = esc.getHold(h).unlockAt;

        vm.warp(unlockAt - 1);
        vm.prank(payer);
        esc.reverse(h); // last second still works

        uint256 h2 = _funded(30e6, 3 days);
        uint64 unlock2 = esc.getHold(h2).unlockAt;
        vm.warp(unlock2);

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Escrow.WindowClosed.selector, unlock2));
        esc.reverse(h2);
    }

    function test_noDoubleReverse() public {
        uint256 h = _funded(30e6, 3 days);
        vm.startPrank(payer);
        esc.reverse(h);
        vm.expectRevert(Escrow.HoldNotOpen.selector);
        esc.reverse(h);
        vm.stopPrank();
    }

    /// The state machine has to be closed in both directions, because every
    /// gap in it is a double spend.
    function test_finalizedCannotBeReversed() public {
        uint256 h = _funded(30e6, 0);
        esc.finalize(h);
        vm.prank(payer);
        vm.expectRevert(Escrow.HoldNotOpen.selector);
        esc.reverse(h);
    }

    function test_reversedCannotBeFinalized() public {
        uint256 h = _funded(30e6, 3 days);
        vm.prank(payer);
        esc.reverse(h);
        vm.warp(block.timestamp + 3 days);
        vm.expectRevert(Escrow.HoldNotOpen.selector);
        esc.finalize(h);
    }

    // --- fees ---

    function test_feeDefaultsToZero() public {
        assertEq(esc.feeBps(), 0);
        uint256 h = _funded(30e6, 0);
        esc.finalize(h);
        assertEq(tok.balanceOf(merchant), 30e6);
        assertEq(esc.accruedFees(address(tok)), 0);
    }

    function test_feeSplitAtFinalize() public {
        vm.prank(owner);
        esc.setFeeBps(50);

        uint256 h = _funded(100e6, 0);
        esc.finalize(h);

        assertEq(tok.balanceOf(merchant), 99.5e6);
        assertEq(esc.accruedFees(address(tok)), 0.5e6);
        _solvent();
    }

    function test_reversalIsFeeFree() public {
        vm.prank(owner);
        esc.setFeeBps(100);

        uint256 h = _funded(100e6, 3 days);
        vm.prank(payer);
        esc.reverse(h);

        assertEq(tok.balanceOf(payer), 100e6, "payer made whole");
        assertEq(esc.accruedFees(address(tok)), 0);
    }

    /// Raising the fee must not reach money already in escrow.
    function test_feeRateIsSnapshotAtOpen() public {
        vm.prank(owner);
        esc.setFeeBps(10);
        uint256 h = _funded(100e6, 3 days);
        assertEq(esc.getHold(h).feeBps, 10);

        vm.prank(owner);
        esc.setFeeBps(100);

        vm.warp(block.timestamp + 3 days);
        esc.finalize(h);
        assertEq(tok.balanceOf(merchant), 99.9e6, "booked rate honoured");
    }

    function test_feeCapIsEnforced() public {
        uint16 maxFee = esc.MAX_FEE_BPS();

        vm.startPrank(owner);
        esc.setFeeBps(maxFee);
        vm.expectRevert(abi.encodeWithSelector(Escrow.FeeTooHigh.selector, maxFee));
        esc.setFeeBps(maxFee + 1);
        vm.stopPrank();
    }

    function test_feeAndSweepAreOwnerOnly() public {
        vm.startPrank(payer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, payer));
        esc.setFeeBps(10);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, payer));
        esc.sweepFees(address(tok), payer);
        vm.stopPrank();
    }

    /// Separate accounting exists so this is impossible: a sweep must never
    /// reach escrowed principal.
    function test_sweepCannotTakePrincipal() public {
        vm.prank(owner);
        esc.setFeeBps(100);

        uint256 settled = _funded(100e6, 0);
        esc.finalize(settled);
        _funded(100e6, 3 days); // still open

        assertEq(tok.balanceOf(address(esc)), 101e6);

        vm.prank(owner);
        assertEq(esc.sweepFees(address(tok), treasury), 1e6);

        assertEq(tok.balanceOf(treasury), 1e6);
        assertEq(esc.totalHeld(address(tok)), 100e6, "principal untouched");
        assertEq(esc.accruedFees(address(tok)), 0);
        _solvent();
    }

    function test_sweepToZeroRejected() public {
        vm.prank(owner);
        vm.expectRevert(Escrow.ZeroRecipient.selector);
        esc.sweepFees(address(tok), address(0));
    }

    function test_sweepOfNothingIsHarmless() public {
        vm.prank(owner);
        assertEq(esc.sweepFees(address(tok), treasury), 0);
    }

    // --- fuzz ---

    function testFuzz_solventUnderMixedOutcomes(uint16 bps, uint96 amount, uint8 pattern) public {
        uint16 rate = uint16(bound(bps, 0, esc.MAX_FEE_BPS()));
        vm.prank(owner);
        esc.setFeeBps(rate);
        uint256 each = bound(amount, 1, 1000e6);

        for (uint256 i; i < 8; ++i) {
            uint256 h = _funded(each, 3 days);
            _solvent();

            if ((pattern >> (i % 8)) & 1 == 1) {
                vm.prank(payer);
                esc.reverse(h);
            } else {
                vm.warp(block.timestamp + 3 days);
                esc.finalize(h);
            }
            _solvent();
        }
        assertEq(esc.totalHeld(address(tok)), 0);
    }

    function testFuzz_feeNeverExceedsAmount(uint16 bps, uint96 amount) public {
        uint16 rate = uint16(bound(bps, 0, esc.MAX_FEE_BPS()));
        vm.prank(owner);
        esc.setFeeBps(rate);
        uint256 a = bound(amount, 1, type(uint96).max);

        uint256 h = _funded(a, 0);
        esc.finalize(h);

        uint256 fee = esc.accruedFees(address(tok));
        assertLe(fee, a / 100, "capped at one percent");
        assertEq(tok.balanceOf(merchant) + fee, a, "nothing lost or created");
    }
}
