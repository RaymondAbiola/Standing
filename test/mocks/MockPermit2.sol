// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IAllowanceTransfer} from "../../src/interfaces/IAllowanceTransfer.sol";

/// Hermetic stand-in for Permit2's AllowanceTransfer.
///
/// Mirrors the real contract's two rules that Standing depends on: an
/// allowance past its expiration is dead, and an allowance of uint160 max is
/// treated as unlimited and never decremented.
contract MockPermit2 is IAllowanceTransfer {
    struct Allow {
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    mapping(address owner => mapping(address token => mapping(address spender => Allow))) internal _allow;

    error InsufficientAllowance();
    error AllowanceExpired();
    error TransferFailed();

    function allowance(address user, address token, address spender)
        external
        view
        returns (uint160, uint48, uint48)
    {
        Allow memory a = _allow[user][token][spender];
        return (a.amount, a.expiration, a.nonce);
    }

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        Allow storage a = _allow[msg.sender][token][spender];
        a.amount = amount;
        a.expiration = expiration;
    }

    function permit(address, PermitSingle memory, bytes calldata) external pure {
        revert("not used");
    }

    function transferFrom(address from, address to, uint160 amount, address token) external {
        Allow storage a = _allow[from][token][msg.sender];
        if (block.timestamp > a.expiration) revert AllowanceExpired();
        if (amount > a.amount) revert InsufficientAllowance();
        if (a.amount != type(uint160).max) a.amount -= amount;

        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", from, to, uint256(amount))
        );
        // Bubble the token's revert rather than masking it, so a test sees
        // which guard actually fired.
        if (!ok) {
            if (data.length > 0) {
                assembly {
                    revert(add(data, 0x20), mload(data))
                }
            }
            revert TransferFailed();
        }
    }
}
