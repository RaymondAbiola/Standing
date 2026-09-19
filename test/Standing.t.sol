// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Standing} from "../src/Standing.sol";
import {Escrow, Hold, HoldStatus} from "../src/base/Escrow.sol";
import {MandateRegistry} from "../src/base/MandateRegistry.sol";
import {Permit2Puller} from "../src/base/Permit2Puller.sol";
import {ChargeKind, Mandate} from "../src/types/Mandate.sol";
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
    uint256 internal payerKey;
    address internal payer;

    uint48 internal permitExpiry;
    uint64 internal window;

    function setUp() public {
        vm.warp(1_000_000);
        permit2 = new MockPermit2();
        std = new Standing(address(permit2), owner);
        token = new MockERC20(0);
        (payer, payerKey) = makeAddrAndKey("payer");
        window = std.DEFAULT_WINDOW();

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
        return Mandate({
            payer: p,
            merchant: merchant,
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
        assertEq(h.unlockAt, uint64(block.timestamp) + window);
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
        uint256 h = std.charge(id, 30e6);

        vm.prank(address(safe));
        std.reverse(h);
        assertEq(uint8(std.getHold(h).status), uint8(HoldStatus.Reversed));
    }

    // --- reversal ---

    function test_payerReversesAndMerchantGetsNothing() public {
        bytes32 id = _mandate();
        uint256 before = token.balanceOf(payer);
        uint256 h = std.charge(id, 30e6);

        vm.prank(payer);
        std.reverse(h);

        assertEq(token.balanceOf(payer), before, "made whole");
        assertEq(token.balanceOf(merchant), 0);
        assertEq(std.totalHeld(address(token)), 0);
        _solvent();
    }

    /// A reversal undoes the money, not the record. The charge still counts
    /// against cadence, so a merchant cannot retry inside the interval.
    function test_reversalDoesNotResetCadence() public {
        bytes32 id = _mandate();
        uint256 h = std.charge(id, 30e6);
        vm.prank(payer);
        std.reverse(h);

        uint64 due = uint64(block.timestamp) + 30 days;
        assertEq(std.nextChargeAt(id), due);
        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.TooSoon.selector, due));
        std.charge(id, 30e6);
        assertEq(std.getMandate(id).chargeCount, 1);
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
        uint256 h = std.charge(id, 30e6);

        vm.startPrank(payer);
        std.revokeMandate(id);
        std.reverse(h);
        vm.stopPrank();

        assertEq(uint8(std.getHold(h).status), uint8(HoldStatus.Reversed));
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
