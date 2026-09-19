// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// The slice of Uniswap's Permit2 AllowanceTransfer that Standing uses.
///
/// Hand-written rather than imported: Permit2's repo pins solc 0.8.17 and
/// brings dependencies this project does not otherwise need.
///
/// Deployed at 0x000000000022D473030F116dDEE9F6B43aC78BA3 on Arbitrum Sepolia,
/// Robinhood Chain and Robinhood Chain testnet, all with identical bytecode.
interface IAllowanceTransfer {
    struct PermitDetails {
        address token;
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    struct PermitSingle {
        PermitDetails details;
        address spender;
        uint256 sigDeadline;
    }

    /// An allowance scoped to an amount and an expiry, which is what makes a
    /// recurring pull possible without an open-ended ERC-20 approval.
    function allowance(address user, address token, address spender)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce);

    function permit(address owner, PermitSingle memory permitSingle, bytes calldata signature) external;

    function approve(address token, address spender, uint160 amount, uint48 expiration) external;

    /// Pulls on behalf of `msg.sender` as spender.
    function transferFrom(address from, address to, uint160 amount, address token) external;
}
