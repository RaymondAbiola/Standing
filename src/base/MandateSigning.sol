// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {Mandate, MandateLib} from "../types/Mandate.sol";

/// EIP-712 domain and payer signature checking.
///
/// Signatures go through SignatureChecker rather than ECDSA directly so that a
/// Safe, or any other ERC-1271 account, can sign a mandate. Most business
/// treasuries are multisigs, so an ECDSA-only path would exclude the market
/// this is built for.
abstract contract MandateSigning is EIP712 {
    error InvalidSignature();

    constructor() EIP712("Standing", "1") {}

    /// The digest a payer signs. Bound to this chain and this contract, so a
    /// mandate signed for one deployment cannot be replayed against another.
    function mandateDigest(Mandate memory m) public view returns (bytes32) {
        return _hashTypedDataV4(MandateLib.hash(m));
    }

    /// Exposed for the SDK, which builds the same digest offchain.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _requireValidSignature(Mandate memory m, bytes calldata signature) internal view {
        if (!SignatureChecker.isValidSignatureNow(m.payer, mandateDigest(m), signature)) {
            revert InvalidSignature();
        }
    }
}
