// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MandateRegistry} from "../src/base/MandateRegistry.sol";
import {Permit2Puller} from "../src/base/Permit2Puller.sol";
import {ChargeKind, Mandate} from "../src/types/Mandate.sol";
import {ChargePathHarness} from "./harness/ChargePathHarness.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";
import {IChargeable, ReenteringToken} from "./mocks/ReenteringToken.sol";

contract ChargePathTest is Test {
    ChargePathHarness internal std;
    MockPermit2 internal permit2;
    MockERC20 internal token;

    address internal merchant = makeAddr("merchant");
    uint256 internal payerKey;
    address internal payer;

    uint48 internal permitExpiry;

    function setUp() public {
        vm.warp(1_000_000);
        permit2 = new MockPermit2();
        std = new ChargePathHarness(address(permit2));
        token = new MockERC20(0);
        (payer, payerKey) = makeAddrAndKey("payer");

        permitExpiry = uint48(block.timestamp + 365 days);
        token.mint(payer, 10_000e6);
        vm.startPrank(payer);
        token.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token), address(std), 1000e6, permitExpiry);
        vm.stopPrank();
    }

    function _terms(address tok) internal view returns (Mandate memory) {
        return Mandate({
            payer: payer,
            merchant: merchant,
            token: tok,
            maxAmount: 30e6,
            minInterval: 30 days,
            startsAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + 3650 days),
            maxCharges: 0,
            chargeKind: ChargeKind.Prepaid,
            salt: bytes32(uint256(1))
        });
    }

    function _create(Mandate memory m) internal returns (bytes32) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(payerKey, std.mandateDigest(m));
        return std.createMandate(m, abi.encodePacked(r, s, v));
    }

    // --- happy path ---

    function test_chargeMovesFundsAndRecords() public {
        bytes32 id = _create(_terms(address(token)));

        std.charge(id, 30e6);

        assertEq(token.balanceOf(address(std)), 30e6);
        assertEq(token.balanceOf(payer), 10_000e6 - 30e6);
        assertEq(std.getMandate(id).chargeCount, 1);
        assertEq(std.getMandate(id).lastChargeAt, uint64(block.timestamp));

        (uint160 remaining,,) = std.permit2Allowance(payer, address(token));
        assertEq(remaining, 1000e6 - 30e6);
    }

    function test_chargeIsPermissionless() public {
        bytes32 id = _create(_terms(address(token)));
        vm.prank(makeAddr("anyone"));
        std.charge(id, 30e6);
        assertEq(token.balanceOf(address(std)), 30e6);
    }

    function test_repeatedChargesAcrossIntervals() public {
        bytes32 id = _create(_terms(address(token)));
        for (uint256 i; i < 4; ++i) {
            std.charge(id, 25e6);
            vm.warp(block.timestamp + 30 days);
        }
        assertEq(token.balanceOf(address(std)), 100e6);
        assertEq(std.getMandate(id).chargeCount, 4);
    }

    function test_partialChargeBelowCap() public {
        bytes32 id = _create(_terms(address(token)));
        std.charge(id, 1);
        assertEq(token.balanceOf(address(std)), 1);
    }

    // --- revert branches ---

    function test_revertsAboveCap() public {
        bytes32 id = _create(_terms(address(token)));
        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.AmountExceedsCap.selector, 30e6));
        std.charge(id, 30e6 + 1);
    }

    function test_revertsOnZeroAmount() public {
        bytes32 id = _create(_terms(address(token)));
        vm.expectRevert(MandateRegistry.ZeroAmount.selector);
        std.charge(id, 0);
    }

    function test_revertsTooSoon() public {
        bytes32 id = _create(_terms(address(token)));
        std.charge(id, 10e6);
        uint64 due = uint64(block.timestamp) + 30 days;

        vm.expectRevert(abi.encodeWithSelector(MandateRegistry.TooSoon.selector, due));
        std.charge(id, 10e6);
    }

    function test_revertsWhenRevoked() public {
        bytes32 id = _create(_terms(address(token)));
        vm.prank(payer);
        std.revokeMandate(id);

        vm.expectRevert(MandateRegistry.NotLive.selector);
        std.charge(id, 10e6);
    }

    function test_revertsAfterRevokeAll() public {
        bytes32 id = _create(_terms(address(token)));
        vm.prank(payer);
        std.revokeAll();

        vm.expectRevert(MandateRegistry.NotLive.selector);
        std.charge(id, 10e6);
    }

    function test_revertsAfterMandateExpiry() public {
        Mandate memory m = _terms(address(token));
        m.expiresAt = uint64(block.timestamp + 10 days);
        bytes32 id = _create(m);

        vm.warp(uint256(m.expiresAt));
        vm.expectRevert(MandateRegistry.NotLive.selector);
        std.charge(id, 10e6);
    }

    function test_revertsOnChargeLimit() public {
        Mandate memory m = _terms(address(token));
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

    /// Mandate revocation and the Permit2 expiry are independent kill
    /// switches: either one alone stops the charge.
    function test_revertsAfterPermit2Expiry() public {
        bytes32 id = _create(_terms(address(token)));
        vm.warp(uint256(permitExpiry) + 1);

        assertTrue(std.isChargeable(id, 10e6));
        vm.expectRevert(MockPermit2.AllowanceExpired.selector);
        std.charge(id, 10e6);
    }

    function test_revertsWhenPermit2AllowanceExhausted() public {
        Mandate memory m = _terms(address(token));
        m.minInterval = 1;
        bytes32 id = _create(m);

        // burn through the 1000e6 Permit2 allowance in 30e6 steps
        for (uint256 i; i < 33; ++i) {
            std.charge(id, 30e6);
            vm.warp(block.timestamp + 1);
        }
        assertEq(token.balanceOf(address(std)), 990e6);

        vm.expectRevert(MockPermit2.InsufficientAllowance.selector);
        std.charge(id, 30e6);
    }

    function test_revertsOnFeeOnTransferToken() public {
        MockERC20 feeToken = new MockERC20(100);
        feeToken.mint(payer, 1000e6);
        vm.startPrank(payer);
        feeToken.approve(address(permit2), type(uint256).max);
        permit2.approve(address(feeToken), address(std), 1000e6, permitExpiry);
        vm.stopPrank();

        bytes32 id = _create(_terms(address(feeToken)));
        vm.expectRevert(Permit2Puller.InexactTransfer.selector);
        std.charge(id, 30e6);
    }

    /// A failed pull must leave no trace, so the mandate is unchanged and a
    /// later charge is still the first one.
    function test_failedPullLeavesNoState() public {
        Mandate memory m = _terms(address(token));
        bytes32 id = _create(m);

        vm.prank(payer);
        permit2.approve(address(token), address(std), 1e6, permitExpiry);

        vm.expectRevert(MockPermit2.InsufficientAllowance.selector);
        std.charge(id, 30e6);

        assertEq(std.getMandate(id).chargeCount, 0);
        assertEq(std.getMandate(id).lastChargeAt, 0);
        assertEq(std.nextChargeAt(id), m.startsAt);
    }

    // --- reentrancy ---

    /// A hostile mandate token that calls back during transferFrom must not
    /// get a second charge inside one interval. Recording before the pull is
    /// what stops it.
    function test_reentrantChargeBlockedByCadence() public {
        ReenteringToken hostile = new ReenteringToken();
        hostile.mint(payer, 1000e6);
        vm.startPrank(payer);
        hostile.approve(address(permit2), type(uint256).max);
        permit2.approve(address(hostile), address(std), 1000e6, permitExpiry);
        vm.stopPrank();

        bytes32 id = _create(_terms(address(hostile)));
        hostile.arm(IChargeable(address(std)), id, 30e6, false);

        vm.expectRevert(
            abi.encodeWithSelector(MandateRegistry.TooSoon.selector, uint64(block.timestamp) + 30 days)
        );
        std.charge(id, 30e6);

        assertEq(std.getMandate(id).chargeCount, 0);
        assertEq(hostile.balanceOf(address(std)), 0);
    }

    /// Same attack against record-after-pull ordering. The cadence guard no
    /// longer catches it, but the exact-transfer guard does, because the
    /// reentrant pull inflates the balance delta the outer pull measures.
    /// Two independent layers, which is why the attack fails either way.
    function test_reentrancyCaughtByExactTransferWhenRecordedLate() public {
        ReenteringToken hostile = new ReenteringToken();
        hostile.mint(payer, 1000e6);
        vm.startPrank(payer);
        hostile.approve(address(permit2), type(uint256).max);
        permit2.approve(address(hostile), address(std), 1000e6, permitExpiry);
        vm.stopPrank();

        bytes32 id = _create(_terms(address(hostile)));
        hostile.arm(IChargeable(address(std)), id, 30e6, true);

        vm.expectRevert(Permit2Puller.InexactTransfer.selector);
        std.chargeRecordLast(id, 30e6);

        assertEq(hostile.balanceOf(address(std)), 0);
        assertEq(std.getMandate(id).chargeCount, 0);
    }

    // --- fuzz ---

    function testFuzz_chargeRespectsCap(uint256 amount) public {
        bytes32 id = _create(_terms(address(token)));
        amount = bound(amount, 1, 100e6);

        if (amount <= 30e6) {
            std.charge(id, amount);
            assertEq(token.balanceOf(address(std)), amount);
        } else {
            vm.expectRevert(abi.encodeWithSelector(MandateRegistry.AmountExceedsCap.selector, 30e6));
            std.charge(id, amount);
        }
    }
}
