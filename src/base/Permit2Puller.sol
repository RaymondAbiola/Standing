// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IAllowanceTransfer} from "../interfaces/IAllowanceTransfer.sol";

// Same address on every chain Standing targets: Arbitrum Sepolia, Robinhood
// Chain and Robinhood Chain testnet, verified to hold identical bytecode.
// File level so deploy scripts can read it without an instance.
address constant CANONICAL_PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

/// Moves funds from the payer into this contract through Permit2.
///
/// Permit2 rather than a direct ERC-20 allowance because it gives the payer an
/// amount-scoped, expiring permission that a spender can draw down repeatedly.
/// A treasury will not hand a billing contract an open-ended approval, and the
/// expiry doubles as a kill switch independent of mandate revocation.
abstract contract Permit2Puller {
    IAllowanceTransfer public immutable PERMIT2;

    error ZeroPermit2();
    error AmountTooLarge();
    error InexactTransfer();

    constructor(address permit2) {
        if (permit2 == address(0)) revert ZeroPermit2();
        PERMIT2 = IAllowanceTransfer(permit2);
    }

    /// What Standing can still pull for this payer and token, so the frontend
    /// can warn before a charge fails.
    function permit2Allowance(address payer, address token)
        external
        view
        returns (uint160 amount, uint48 expiration, uint48 nonce)
    {
        return PERMIT2.allowance(payer, token, address(this));
    }

    /// Pulls exactly `amount` into this contract.
    ///
    /// The balance delta is asserted rather than trusted. A fee-on-transfer or
    /// rebasing token would credit escrow with less than the payer was debited,
    /// and every downstream balance would drift. Those tokens are out of scope,
    /// so the safe behaviour is to refuse the charge rather than book a hold
    /// that cannot be paid out.
    function _pullExact(address token, address from, uint256 amount) internal {
        if (amount > type(uint160).max) revert AmountTooLarge();

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        // Safe: the bound above rejects anything a uint160 could not hold.
        // forge-lint: disable-next-line(unsafe-typecast)
        PERMIT2.transferFrom(from, address(this), uint160(amount), token);
        uint256 received = IERC20(token).balanceOf(address(this)) - balanceBefore;

        if (received != amount) revert InexactTransfer();
    }
}
