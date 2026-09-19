// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Escrow} from "./base/Escrow.sol";
import {MandateRecord, MandateRegistry} from "./base/MandateRegistry.sol";
import {Permit2Puller} from "./base/Permit2Puller.sol";
import {ChargeKind} from "./types/Mandate.sol";

/// Standing: recurring stablecoin payments with recourse.
///
/// A charge pulls from the payer through Permit2 and books the funds into
/// escrow behind an unlock time. The merchant is paid when the window closes.
/// Earned reversal rights, which decide whether a payer may pull a hold back
/// inside that window, land next.
contract Standing is MandateRegistry, Permit2Puller, Escrow {
    /// Placeholder policy. The window becomes a function of merchant history,
    /// shortening as a merchant earns trust, once the merchant registry lands.
    uint64 public constant DEFAULT_WINDOW = 3 days;

    event Charged(
        bytes32 indexed id,
        address indexed merchant,
        address indexed payer,
        uint256 holdId,
        address token,
        uint256 amount,
        uint32 chargeCount
    );

    constructor(address permit2) Permit2Puller(permit2) {}

    /// Permissionless. The merchant normally calls it, which is the right
    /// incentive since the merchant wants the revenue and pays the gas.
    ///
    /// Ordering is load bearing. `_recordCharge` runs before the pull, because
    /// the pull hands control to the token and a hostile token reentering
    /// while `lastChargeAt` still held its old value would clear the cadence
    /// check twice. The hold is booked after the funds have actually arrived,
    /// so escrow never promises money it does not hold.
    function charge(bytes32 id, uint256 amount) external returns (uint256 holdId) {
        MandateRecord storage r = _requireChargeable(id, amount);
        _recordCharge(r);

        address token = r.terms.token;
        address payer = r.terms.payer;
        address merchant = r.terms.merchant;
        uint64 window = _windowFor(r.terms.chargeKind);

        _pullExact(token, payer, amount);
        holdId = _openHold(id, payer, merchant, token, amount, window);

        emit Charged(id, merchant, payer, holdId, token, amount, r.chargeCount);
    }

    /// Postpaid charges bill for consumption that already happened, so they
    /// carry no reversal right and settle without a window.
    function _windowFor(ChargeKind kind) internal pure returns (uint64) {
        return kind == ChargeKind.Postpaid ? 0 : DEFAULT_WINDOW;
    }
}
