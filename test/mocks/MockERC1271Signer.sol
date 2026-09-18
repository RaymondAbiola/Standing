// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// Stands in for a Safe: a contract account that approves a digest when the
/// signature recovers to its owner.
contract MockERC1271Signer is IERC1271 {
    address public immutable OWNER;

    constructor(address owner) {
        OWNER = owner;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        if (err == ECDSA.RecoverError.NoError && recovered == OWNER) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }
}

/// A contract account that refuses everything, for the rejection path.
contract MockRejectingSigner is IERC1271 {
    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        return 0xffffffff;
    }
}
