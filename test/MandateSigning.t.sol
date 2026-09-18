// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {MandateSigning} from "../src/base/MandateSigning.sol";
import {ChargeKind, Mandate, MandateLib} from "../src/types/Mandate.sol";
import {MandateSigningHarness} from "./harness/MandateSigningHarness.sol";
import {MockERC1271Signer, MockRejectingSigner} from "./mocks/MockERC1271Signer.sol";

contract MandateSigningTest is Test {
    /// Recomputed by hand with `cast keccak`. If a struct field is renamed,
    /// retyped or reordered, this fixture breaks instead of silently changing
    /// the digest that payers have already signed.
    bytes32 internal constant EXPECTED_TYPEHASH =
        0x8d54aafac111f5925e5a26ce70d61cde1b66ea2cec8b66cfe5bc7ff3840c568f;

    bytes32 internal constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    MandateSigningHarness internal signing;

    address internal merchant = makeAddr("merchant");
    address internal token = makeAddr("token");

    uint256 internal payerKey;
    address internal payer;

    function setUp() public {
        signing = new MandateSigningHarness();
        (payer, payerKey) = makeAddrAndKey("payer");
    }

    function _mandate(address payer_) internal view returns (Mandate memory) {
        return Mandate({
            payer: payer_,
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, signing.mandateDigest(m));
        return abi.encodePacked(r, s, v);
    }

    /// Hand-rolled EIP-712, deliberately not reusing MandateLib, so the test
    /// is an independent check rather than a re-run of the implementation.
    function _handRolledDigest(Mandate memory m, address verifying) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                EXPECTED_TYPEHASH,
                m.payer,
                m.merchant,
                m.token,
                m.maxAmount,
                m.minInterval,
                m.startsAt,
                m.expiresAt,
                m.maxCharges,
                uint8(m.chargeKind),
                m.salt
            )
        );
        bytes32 domain = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("Standing"), keccak256("1"), block.chainid, verifying)
        );
        return keccak256(abi.encodePacked(hex"1901", domain, structHash));
    }

    function test_typehashMatchesFixture() public pure {
        assertEq(MandateLib.MANDATE_TYPEHASH, EXPECTED_TYPEHASH);
    }

    function test_domainSeparatorMatchesHandRolled() public view {
        bytes32 expected = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256("Standing"), keccak256("1"), block.chainid, address(signing)
            )
        );
        assertEq(signing.domainSeparator(), expected);
    }

    function testFuzz_digestMatchesHandRolled(
        address payer_,
        uint256 maxAmount,
        uint64 minInterval,
        uint64 startsAt,
        uint64 expiresAt,
        uint32 maxCharges,
        bool postpaid,
        bytes32 salt
    ) public view {
        Mandate memory m = Mandate({
            payer: payer_,
            merchant: merchant,
            token: token,
            maxAmount: maxAmount,
            minInterval: minInterval,
            startsAt: startsAt,
            expiresAt: expiresAt,
            maxCharges: maxCharges,
            chargeKind: postpaid ? ChargeKind.Postpaid : ChargeKind.Prepaid,
            salt: salt
        });
        assertEq(signing.mandateDigest(m), _handRolledDigest(m, address(signing)));
    }

    function test_eoaSignatureValidates() public view {
        Mandate memory m = _mandate(payer);
        signing.requireValidSignature(m, _sign(payerKey, m));
    }

    function test_revertsOnWrongSigner() public {
        (, uint256 otherKey) = makeAddrAndKey("other");
        Mandate memory m = _mandate(payer);
        bytes memory sig = _sign(otherKey, m);

        vm.expectRevert(MandateSigning.InvalidSignature.selector);
        signing.requireValidSignature(m, sig);
    }

    /// A signature is bound to the exact terms, so raising the cap after
    /// signing must invalidate it.
    function test_revertsOnTamperedAmount() public {
        Mandate memory m = _mandate(payer);
        bytes memory sig = _sign(payerKey, m);
        m.maxAmount = 3000e6;

        vm.expectRevert(MandateSigning.InvalidSignature.selector);
        signing.requireValidSignature(m, sig);
    }

    /// The path that matters for real payers: a multisig treasury signing a
    /// mandate through ERC-1271 rather than as an EOA.
    function test_erc1271SignerValidates() public {
        MockERC1271Signer safe = new MockERC1271Signer(payer);
        Mandate memory m = _mandate(address(safe));
        signing.requireValidSignature(m, _sign(payerKey, m));
    }

    function test_revertsWhenErc1271Rejects() public {
        MockRejectingSigner safe = new MockRejectingSigner();
        Mandate memory m = _mandate(address(safe));
        bytes memory sig = _sign(payerKey, m);

        vm.expectRevert(MandateSigning.InvalidSignature.selector);
        signing.requireValidSignature(m, sig);
    }

    function test_revertsWhenErc1271OwnerDiffers() public {
        (address otherOwner,) = makeAddrAndKey("otherOwner");
        MockERC1271Signer safe = new MockERC1271Signer(otherOwner);
        Mandate memory m = _mandate(address(safe));
        bytes memory sig = _sign(payerKey, m);

        vm.expectRevert(MandateSigning.InvalidSignature.selector);
        signing.requireValidSignature(m, sig);
    }

    function test_saltChangesMandateId() public view {
        Mandate memory a = _mandate(payer);
        Mandate memory b = _mandate(payer);
        b.salt = bytes32(uint256(2));
        assertTrue(MandateLib.hash(a) != MandateLib.hash(b));
    }

    function test_chargeKindChangesMandateId() public view {
        Mandate memory a = _mandate(payer);
        Mandate memory b = _mandate(payer);
        b.chargeKind = ChargeKind.Postpaid;
        assertTrue(MandateLib.hash(a) != MandateLib.hash(b));
    }

    /// We deploy to Arbitrum Sepolia and Robinhood Chain, so a mandate signed
    /// for one deployment must not be replayable against the other.
    function test_digestIsBoundToDeployment() public {
        MandateSigningHarness other = new MandateSigningHarness();
        Mandate memory m = _mandate(payer);
        assertTrue(signing.mandateDigest(m) != other.mandateDigest(m));
    }

    function test_signatureFromOneDeploymentFailsOnAnother() public {
        MandateSigningHarness other = new MandateSigningHarness();
        Mandate memory m = _mandate(payer);
        bytes memory sig = _sign(payerKey, m);

        vm.expectRevert(MandateSigning.InvalidSignature.selector);
        other.requireValidSignature(m, sig);
    }
}
