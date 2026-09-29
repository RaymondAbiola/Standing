// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {Standing} from "../src/Standing.sol";
import {ChargeKind, Mandate} from "../src/types/Mandate.sol";
import {ReversalBlock} from "../src/types/Reversal.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";

/// The attack the whole standing mechanism exists to price.
///
/// Create a fresh address, sign a mandate, consume a cycle, reverse the
/// charge, discard the address, repeat. Addresses are free, so any reputation
/// attached to one is worth what it cost to make.
///
/// These tests measure what the attack actually yields rather than asserting
/// that it reverts, because "it reverts" is not the claim. The claim is that
/// it is unprofitable.
contract SybilTest is Test {
    uint256 internal constant CYCLE = 30e6;

    Standing internal std;
    MockPermit2 internal permit2;
    MockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal merchant = makeAddr("merchant");
    uint64 internal window;

    uint256 internal nextAttacker;

    function setUp() public {
        vm.warp(1_000_000);
        permit2 = new MockPermit2();
        std = new Standing(address(permit2), owner);
        token = new MockERC20(0);
        window = std.MAX_MERCHANT_WINDOW();
    }

    /// A brand new funded address, which is all an attacker ever has.
    function _freshPayer() internal returns (address payer, uint256 key) {
        nextAttacker += 1;
        (payer, key) = makeAddrAndKey(string(abi.encodePacked("attacker", vm.toString(nextAttacker))));

        token.mint(payer, 10_000e6);
        vm.startPrank(payer);
        token.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token), address(std), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _mandate(address payer, uint256 key, address mrc, uint256 cap, bytes32 salt)
        internal
        returns (bytes32)
    {
        Mandate memory m = Mandate({
            payer: payer,
            merchant: mrc,
            token: address(token),
            maxAmount: cap,
            minInterval: 1,
            startsAt: uint64(block.timestamp),
            expiresAt: type(uint64).max,
            maxCharges: 0,
            chargeKind: ChargeKind.Prepaid,
            salt: salt
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, std.mandateDigest(m));
        return std.createMandate(m, abi.encodePacked(r, s, v));
    }

    function _payCleanly(bytes32 id, uint256 amount) internal {
        uint256 h = std.charge(id, amount);
        vm.warp(block.timestamp + window);
        std.finalize(h);
        vm.warp(block.timestamp + 1);
    }

    /// The core case. A fresh address has settled nothing, holds no reversal
    /// right, and takes nothing.
    function test_freshAddressClawbackYieldsZero() public {
        (address payer, uint256 key) = _freshPayer();
        bytes32 id = _mandate(payer, key, merchant, CYCLE, bytes32(uint256(1)));

        uint256 h = std.charge(id, CYCLE);
        assertEq(uint8(std.reversalBlocker(h, payer)), uint8(ReversalBlock.NotVested));

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Standing.NotVested.selector, uint32(0), uint32(3)));
        std.reverse(h);

        vm.warp(block.timestamp + window);
        std.finalize(h);
        assertEq(token.balanceOf(merchant), CYCLE, "merchant kept it");
    }

    /// Churning addresses does not help, because the thing being churned has
    /// no value. Twenty fresh identities steal nothing between them.
    function test_churningIdentitiesStealsNothing() public {
        uint256 attempts = 20;

        for (uint256 i; i < attempts; ++i) {
            (address payer, uint256 key) = _freshPayer();
            bytes32 id = _mandate(payer, key, merchant, CYCLE, bytes32(i + 100));

            uint256 h = std.charge(id, CYCLE);
            vm.prank(payer);
            vm.expectRevert(abi.encodeWithSelector(Standing.NotVested.selector, uint32(0), uint32(3)));
            std.reverse(h);

            vm.warp(block.timestamp + window);
            std.finalize(h);
            vm.warp(block.timestamp + 1);
        }

        assertEq(token.balanceOf(merchant), attempts * CYCLE, "every attempt paid in full");
        assertEq(std.totalHeld(address(token)), 0);
    }

    /// What the attack costs once it is actually possible. Three cycles have
    /// to be paid before one can be taken, so the merchant is ahead on every
    /// attacker who tries, and the attacker's discount is capped at a quarter
    /// before service is withdrawn.
    function test_attackerMustPayThreeCyclesToTakeOne() public {
        (address payer, uint256 key) = _freshPayer();
        bytes32 id = _mandate(payer, key, merchant, CYCLE, bytes32(uint256(2)));

        for (uint256 i; i < 3; ++i) {
            _payCleanly(id, CYCLE);
        }
        assertTrue(std.isVested(payer));
        assertEq(std.reversalCeiling(payer), CYCLE);

        uint256 stolen = std.charge(id, CYCLE);
        vm.prank(payer);
        std.reverse(stolen);

        uint256 merchantRevenue = token.balanceOf(merchant);
        uint256 cyclesConsumed = 4;

        assertEq(merchantRevenue, 3 * CYCLE, "merchant net positive by two cycles");
        console.log("cycles consumed  ", cyclesConsumed);
        console.log("cycles paid for  ", merchantRevenue / CYCLE);
        console.log("attacker discount", ((cyclesConsumed - 3) * 100) / cyclesConsumed, "percent");
    }

    /// Cheap history cannot unlock expensive theft. Vesting on dust leaves a
    /// ceiling measured in dust.
    function test_launderingCheapHistoryDoesNotUnlockLargeReversal() public {
        (address payer, uint256 key) = _freshPayer();
        bytes32 cheap = _mandate(payer, key, merchant, CYCLE, bytes32(uint256(3)));

        for (uint256 i; i < 3; ++i) {
            _payCleanly(cheap, 1e6);
        }
        assertTrue(std.isVested(payer), "vested on three dust payments");
        assertEq(std.reversalCeiling(payer), 1e6, "but the ceiling is dust too");

        uint256 big = std.charge(cheap, CYCLE);
        assertEq(uint8(std.reversalBlocker(big, payer)), uint8(ReversalBlock.AboveCeiling));

        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Standing.AboveReversalCeiling.selector, 1e6));
        std.reverse(big);
    }

    /// Spreading the attack across merchants to look like an ordinary disputer
    /// is what the dispersion signal is for: it suspends the right.
    function test_spreadingTheAttackAcrossMerchantsSuspends() public {
        (address payer, uint256 key) = _freshPayer();
        address mB = makeAddr("merchantB");
        address mC = makeAddr("merchantC");

        bytes32 a = _mandate(payer, key, merchant, CYCLE, bytes32(uint256(4)));
        bytes32 b = _mandate(payer, key, mB, CYCLE, bytes32(uint256(5)));
        bytes32 c = _mandate(payer, key, mC, CYCLE, bytes32(uint256(6)));

        for (uint256 i; i < 3; ++i) {
            _payCleanly(a, CYCLE);
        }

        _takeOne(a, payer);
        _takeOne(b, payer);
        _takeOne(c, payer);

        assertTrue(std.isSuspended(payer), "pattern recognised");
        assertEq(std.cyclesUntilRestored(payer), 3);

        uint256 next = std.charge(a, CYCLE);
        assertEq(uint8(std.reversalBlocker(next, payer)), uint8(ReversalBlock.Suspended));
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Standing.ReversalSuspended.selector, uint32(3)));
        std.reverse(next);
    }

    function _takeOne(bytes32 id, address payer) internal {
        uint256 h = std.charge(id, CYCLE);
        vm.prank(payer);
        std.reverse(h);
        vm.warp(block.timestamp + 1);
    }

    /// A limit worth stating rather than hiding.
    ///
    /// Against one merchant, a vested payer can reverse every cycle without
    /// ever tripping suspension, because dispersion deliberately never counts
    /// a single counterparty: that pattern is evidence about the merchant, and
    /// reading it as payer abuse would punish the customers of a broken
    /// integration.
    ///
    /// The bound on this is not onchain. The merchant withdraws service on the
    /// first reversal, reversal history is public before a merchant accepts a
    /// mandate, and the merchant's acceptance policy refuses payers whose
    /// standing it does not like. This test exists so that limit is explicit
    /// and so a change to the dispersion rule has to confront it.
    function test_singleMerchantRepeatReversalIsNotSuspendedOnchain() public {
        (address payer, uint256 key) = _freshPayer();
        bytes32 id = _mandate(payer, key, merchant, CYCLE, bytes32(uint256(7)));

        for (uint256 i; i < 3; ++i) {
            _payCleanly(id, CYCLE);
        }

        for (uint256 i; i < 5; ++i) {
            _takeOne(id, payer);
        }

        assertEq(std.standingOf(payer).reversals, 5);
        assertEq(std.standingOf(payer).distinctMerchantsReversed, 1);
        assertFalse(std.isSuspended(payer), "not suspended, by design");

        // The ceiling does not grow while this is happening, because reversed
        // value never counts as clean, so the size of each theft is frozen at
        // what the payer had already settled.
        assertEq(std.reversalCeiling(payer), CYCLE);
        assertEq(std.standingOf(payer).cumulativeCleanSettled, 3 * CYCLE);
    }

    /// Whatever the pattern, the contract stays solvent and nothing is
    /// created. An attacker cannot extract more than was put in.
    function testFuzz_attackNeverBreaksConservation(uint8 pattern, uint8 rounds) public {
        (address payer, uint256 key) = _freshPayer();
        bytes32 id = _mandate(payer, key, merchant, CYCLE, bytes32(uint256(8)));

        uint256 minted = token.balanceOf(payer);
        uint256 n = bound(rounds, 1, 10);

        for (uint256 i; i < n; ++i) {
            uint256 h = std.charge(id, CYCLE);

            if ((pattern >> (i % 8)) & 1 == 1 && std.canReverse(h, payer)) {
                vm.prank(payer);
                std.reverse(h);
            } else {
                vm.warp(block.timestamp + window);
                std.finalize(h);
            }
            vm.warp(block.timestamp + 1);

            assertGe(
                token.balanceOf(address(std)),
                std.totalHeld(address(token)) + std.accruedFees(address(token)),
                "solvent"
            );
        }

        assertEq(
            token.balanceOf(payer) + token.balanceOf(merchant) + token.balanceOf(address(std)),
            minted,
            "nothing created or destroyed"
        );
    }
}
