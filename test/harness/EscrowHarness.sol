// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Escrow} from "../../src/base/Escrow.sol";

/// Escrow with no mandate registry and no Permit2 in the way, so hold
/// mechanics can be tested on their own. Tests mint straight to this contract
/// to stand in for a pull having already happened.
contract EscrowHarness is Escrow {
    constructor(address initialOwner) Escrow(initialOwner) {}

    /// Escrow's settlement paths are internal now, with the external entry
    /// points on Standing. These wrappers keep the vault testable on its own.
    function finalize(uint256 holdId) external {
        _finalizeHold(holdId);
    }

    function reverse(uint256 holdId) external {
        _reverseHold(holdId);
    }

    function open(
        bytes32 mandateId,
        address payer,
        address merchant,
        address token,
        uint256 amount,
        uint64 window
    ) external returns (uint256) {
        return _openHold(mandateId, payer, merchant, token, amount, window);
    }
}
