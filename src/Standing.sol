// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MandateRecord, MandateRegistry} from "./base/MandateRegistry.sol";
import {Permit2Puller} from "./base/Permit2Puller.sol";

/// Standing: recurring stablecoin payments with recourse.
///
/// v0. The mandate, its cadence and its caps are in place and enforced. The
/// escrow window is not: a charge pays the merchant in the same call, so there
/// is nothing to reverse yet. `charge` changes shape when escrow lands and the
/// payout moves behind an unlock time.
///
/// Deployed early on testnet on purpose, to prove the deploy and verification
/// path rather than discovering it on the last day.
contract Standing is MandateRegistry, Permit2Puller {
    using SafeERC20 for IERC20;

    event Charged(
        bytes32 indexed id,
        address indexed merchant,
        address indexed payer,
        address token,
        uint256 amount,
        uint32 chargeCount
    );

    constructor(address permit2) Permit2Puller(permit2) {}

    /// Permissionless. The merchant normally calls it, which is the right
    /// incentive since the merchant wants the revenue and pays the gas.
    ///
    /// `_recordCharge` runs before the pull, not after. The pull hands control
    /// to the token, and a hostile token that reentered while `lastChargeAt`
    /// still held its old value would clear the cadence check twice. Note the
    /// exact-transfer guard does not cover this case here, because forwarding
    /// to the merchant leaves the measured balance delta looking correct.
    function charge(bytes32 id, uint256 amount) external {
        MandateRecord storage r = _requireChargeable(id, amount);
        _recordCharge(r);

        address token = r.terms.token;
        address merchant = r.terms.merchant;

        _pullExact(token, r.terms.payer, amount);
        IERC20(token).safeTransfer(merchant, amount);

        emit Charged(id, merchant, r.terms.payer, token, amount, r.chargeCount);
    }
}
