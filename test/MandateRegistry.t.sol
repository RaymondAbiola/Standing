// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MandateRecord, MandateRegistry, MandateStatus} from "../src/base/MandateRegistry.sol";
import {MandateSigning} from "../src/base/MandateSigning.sol";
import {ChargeKind, Mandate} from "../src/types/Mandate.sol";
import {MandateRegistryHarness} from "./harness/MandateRegistryHarness.sol";
import {MockERC1271Signer} from "./mocks/MockERC1271Signer.sol";

contract MandateRegistryTest is Test {
    event MandateCreated(
        bytes32 indexed id,
        address indexed payer,
        address indexed merchant,
        address token,
        uint256 maxAmount,
        uint64 minInterval,
        uint64 expiresAt,
        uint32 epoch
    );

    event MandateRevoked(bytes32 indexed id, address indexed payer);
    event PayerEpochBumped(address indexed payer, uint32 epoch);

    MandateRegistryHarness internal reg;

    address internal merchant = makeAddr("merchant");
    address internal token = makeAddr("token");
    address internal relayer = makeAddr("relayer");

    uint256 internal payerKey;
    address internal payer;

    function setUp() public {
        reg = new MandateRegistryHarness();
        (payer, payerKey) = makeAddrAndKey("payer");
        vm.warp(1_000_000);
    }

    function _terms() internal view returns (Mandate memory) {
        return Mandate({
            payer: payer,
            merchant: merchant,
            token: token,
            maxAmount: 30e6,
            minInterval: 30 days,
            startsAt: uint64(block.timestamp),
            expiresAt: uint64(block.timestamp + 365 days),
            maxCharges: 0,
            chargeKind: ChargeKind.Prepaid,
            salt: bytes32(uint256(1))
        });
    }

    function _sign(uint256 key, Mandate memory m) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, reg.mandateDigest(m));
        return abi.encodePacked(r, s, v);
    }

    /// The signature has to be built before `expectRevert`, because building it
    /// calls `mandateDigest` on the registry and would otherwise consume the
    /// expectation.
    function _expectCreateRevert(Mandate memory m, bytes4 err) internal {
        bytes memory sig = _sign(payerKey, m);
        vm.expectRevert(err);
        reg.createMandate(m, sig);
    }

    // --- creation ---

    function test_createStoresTermsAndReturnsId() public {
        Mandate memory m = _terms();
        bytes32 id = reg.createMandate(m, _sign(payerKey, m));

        assertEq(id, reg.mandateId(m));

        MandateRecord memory r = reg.getMandate(id);
        assertEq(uint8(r.status), uint8(MandateStatus.Active));
        assertEq(r.epoch, 0);
        assertEq(r.chargeCount, 0);
        assertEq(r.lastChargeAt, 0);
        assertEq(r.createdAt, uint64(block.timestamp));

        assertEq(r.terms.payer, payer);
        assertEq(r.terms.merchant, merchant);
        assertEq(r.terms.token, token);
        assertEq(r.terms.maxAmount, 30e6);
        assertEq(r.terms.minInterval, 30 days);
        assertEq(r.terms.maxCharges, 0);
        assertEq(uint8(r.terms.chargeKind), uint8(ChargeKind.Prepaid));
        assertEq(r.terms.salt, bytes32(uint256(1)));
    }

    function test_createEmitsEvent() public {
        Mandate memory m = _terms();
        bytes memory sig = _sign(payerKey, m);

        vm.expectEmit(true, true, true, true);
        emit MandateCreated(reg.mandateId(m), payer, merchant, token, 30e6, 30 days, m.expiresAt, 0);
        reg.createMandate(m, sig);
    }

    /// Anyone can submit: the payer's signature is the authorisation, so the
    /// merchant pays the gas for the revenue it wants.
    function test_createIsPermissionless() public {
        Mandate memory m = _terms();
        bytes memory sig = _sign(payerKey, m);

        vm.prank(relayer);
        bytes32 id = reg.createMandate(m, sig);
        assertTrue(reg.isMandateLive(id));
    }

    function test_createRevertsOnBadSignature() public {
        (, uint256 otherKey) = makeAddrAndKey("other");
        Mandate memory m = _terms();
        bytes memory sig = _sign(otherKey, m);

        vm.expectRevert(MandateSigning.InvalidSignature.selector);
        reg.createMandate(m, sig);
    }

    function test_safePayerCanCreate() public {
        MockERC1271Signer safe = new MockERC1271Signer(payer);
        Mandate memory m = _terms();
        m.payer = address(safe);

        bytes32 id = reg.createMandate(m, _sign(payerKey, m));
        assertTrue(reg.isMandateLive(id));
    }

    function test_distinctSaltsCoexist() public {
        Mandate memory a = _terms();
        Mandate memory b = _terms();
        b.salt = bytes32(uint256(2));

        bytes32 idA = reg.createMandate(a, _sign(payerKey, a));
        bytes32 idB = reg.createMandate(b, _sign(payerKey, b));

        assertTrue(idA != idB);
        assertTrue(reg.isMandateLive(idA));
        assertTrue(reg.isMandateLive(idB));
    }

    // --- replay ---

    function test_replayOfSameSignatureReverts() public {
        Mandate memory m = _terms();
        bytes memory sig = _sign(payerKey, m);
        reg.createMandate(m, sig);

        vm.expectRevert(MandateRegistry.MandateExists.selector);
        reg.createMandate(m, sig);
    }

    /// Records are never cleared, which is the only thing stopping a revoked
    /// mandate's still-valid signature from resurrecting it.
    function test_cannotRecreateRevokedMandate() public {
        Mandate memory m = _terms();
        bytes memory sig = _sign(payerKey, m);
        bytes32 id = reg.createMandate(m, sig);

        vm.prank(payer);
        reg.revokeMandate(id);

        vm.expectRevert(MandateRegistry.MandateExists.selector);
        reg.createMandate(m, sig);
    }

    // --- terms validation ---

    function test_createRevertsOnZeroPayer() public {
        Mandate memory m = _terms();
        m.payer = address(0);
        _expectCreateRevert(m, MandateRegistry.ZeroAddress.selector);
    }

    function test_createRevertsOnZeroMerchant() public {
        Mandate memory m = _terms();
        m.merchant = address(0);
        _expectCreateRevert(m, MandateRegistry.ZeroAddress.selector);
    }

    function test_createRevertsOnZeroToken() public {
        Mandate memory m = _terms();
        m.token = address(0);
        _expectCreateRevert(m, MandateRegistry.ZeroAddress.selector);
    }

    function test_createRevertsOnZeroAmount() public {
        Mandate memory m = _terms();
        m.maxAmount = 0;
        _expectCreateRevert(m, MandateRegistry.ZeroAmount.selector);
    }

    /// A zero interval would let a merchant drain the cap every block, which
    /// defeats the cadence guarantee the payer signed up for.
    function test_createRevertsOnZeroInterval() public {
        Mandate memory m = _terms();
        m.minInterval = 0;
        _expectCreateRevert(m, MandateRegistry.ZeroInterval.selector);
    }

    function test_createRevertsOnAlreadyExpired() public {
        Mandate memory m = _terms();
        m.expiresAt = uint64(block.timestamp - 1);
        _expectCreateRevert(m, MandateRegistry.BadWindow.selector);
    }

    function test_createRevertsOnEmptyWindow() public {
        Mandate memory m = _terms();
        m.startsAt = uint64(block.timestamp + 10 days);
        m.expiresAt = m.startsAt;
        _expectCreateRevert(m, MandateRegistry.BadWindow.selector);
    }

    // --- revocation ---

    function test_revokeIsImmediateAndPayerOnly() public {
        Mandate memory m = _terms();
        bytes32 id = reg.createMandate(m, _sign(payerKey, m));

        vm.prank(merchant);
        vm.expectRevert(MandateRegistry.NotPayer.selector);
        reg.revokeMandate(id);

        vm.expectEmit(true, true, false, false);
        emit MandateRevoked(id, payer);
        vm.prank(payer);
        reg.revokeMandate(id);

        // same block, no delay the merchant can exploit
        assertFalse(reg.isMandateLive(id));
        assertEq(uint8(reg.getMandate(id).status), uint8(MandateStatus.Revoked));
    }

    function test_revokeTwiceReverts() public {
        Mandate memory m = _terms();
        bytes32 id = reg.createMandate(m, _sign(payerKey, m));

        vm.prank(payer);
        reg.revokeMandate(id);

        vm.prank(payer);
        vm.expectRevert(MandateRegistry.NotActive.selector);
        reg.revokeMandate(id);
    }

    function test_revokeUnknownReverts() public {
        vm.expectRevert(MandateRegistry.UnknownMandate.selector);
        reg.revokeMandate(keccak256("absent"));
    }

    function test_safePayerCanRevoke() public {
        MockERC1271Signer safe = new MockERC1271Signer(payer);
        Mandate memory m = _terms();
        m.payer = address(safe);
        bytes32 id = reg.createMandate(m, _sign(payerKey, m));

        vm.prank(address(safe));
        reg.revokeMandate(id);
        assertFalse(reg.isMandateLive(id));
    }

    // --- payer epoch ---

    function test_revokeAllKillsOutstandingWithoutTouchingRecords() public {
        Mandate memory a = _terms();
        Mandate memory b = _terms();
        b.salt = bytes32(uint256(2));
        bytes32 idA = reg.createMandate(a, _sign(payerKey, a));
        bytes32 idB = reg.createMandate(b, _sign(payerKey, b));

        vm.expectEmit(true, false, false, true);
        emit PayerEpochBumped(payer, 1);
        vm.prank(payer);
        assertEq(reg.revokeAll(), 1);

        assertFalse(reg.isMandateLive(idA));
        assertFalse(reg.isMandateLive(idB));

        // the bump is O(1), so status stays Active and only liveness changes
        assertEq(uint8(reg.getMandate(idA).status), uint8(MandateStatus.Active));
        assertEq(reg.getMandate(idA).epoch, 0);
        assertEq(reg.payerEpoch(payer), 1);
    }

    function test_mandateCreatedAfterBumpIsLive() public {
        Mandate memory a = _terms();
        bytes32 idA = reg.createMandate(a, _sign(payerKey, a));

        vm.prank(payer);
        reg.revokeAll();

        Mandate memory b = _terms();
        b.salt = bytes32(uint256(9));
        bytes32 idB = reg.createMandate(b, _sign(payerKey, b));

        assertFalse(reg.isMandateLive(idA));
        assertTrue(reg.isMandateLive(idB));
        assertEq(reg.getMandate(idB).epoch, 1);
    }

    /// A gotcha worth pinning: after `revokeAll` the payer cannot re-sign the
    /// same terms, because the id is the struct hash and that record exists.
    /// Reinstating a mandate requires a fresh salt.
    function test_cannotReviveSameTermsAfterBump() public {
        Mandate memory m = _terms();
        bytes memory sig = _sign(payerKey, m);
        reg.createMandate(m, sig);

        vm.prank(payer);
        reg.revokeAll();

        vm.expectRevert(MandateRegistry.MandateExists.selector);
        reg.createMandate(m, sig);
    }

    function test_epochIsPerPayer() public {
        vm.prank(payer);
        reg.revokeAll();

        assertEq(reg.payerEpoch(payer), 1);
        assertEq(reg.payerEpoch(merchant), 0);
    }

    // --- liveness window ---

    function test_notLiveBeforeStart() public {
        Mandate memory m = _terms();
        m.startsAt = uint64(block.timestamp + 10 days);
        bytes32 id = reg.createMandate(m, _sign(payerKey, m));

        assertFalse(reg.isMandateLive(id));
        vm.warp(m.startsAt);
        assertTrue(reg.isMandateLive(id));
    }

    function test_notLiveAtExpiry() public {
        Mandate memory m = _terms();
        bytes32 id = reg.createMandate(m, _sign(payerKey, m));

        vm.warp(uint256(m.expiresAt) - 1);
        assertTrue(reg.isMandateLive(id));
        vm.warp(uint256(m.expiresAt));
        assertFalse(reg.isMandateLive(id));
    }

    function test_unknownMandateIsNotLive() public view {
        assertFalse(reg.isMandateLive(keccak256("absent")));
    }

    // --- fuzz ---

    function testFuzz_createAcceptsAnyValidTerms(
        uint256 maxAmount,
        uint64 minInterval,
        uint64 offset,
        uint64 duration,
        uint32 maxCharges,
        bool postpaid,
        bytes32 salt
    ) public {
        maxAmount = bound(maxAmount, 1, type(uint256).max);
        minInterval = uint64(bound(minInterval, 1, 365 days));
        offset = uint64(bound(offset, 0, 365 days));
        duration = uint64(bound(duration, 1, 365 days));

        Mandate memory m = Mandate({
            payer: payer,
            merchant: merchant,
            token: token,
            maxAmount: maxAmount,
            minInterval: minInterval,
            startsAt: uint64(block.timestamp) + offset,
            expiresAt: uint64(block.timestamp) + offset + duration,
            maxCharges: maxCharges,
            chargeKind: postpaid ? ChargeKind.Postpaid : ChargeKind.Prepaid,
            salt: salt
        });

        bytes32 id = reg.createMandate(m, _sign(payerKey, m));
        assertEq(uint8(reg.getMandate(id).status), uint8(MandateStatus.Active));
        assertEq(reg.getMandate(id).terms.maxAmount, maxAmount);
    }
}
