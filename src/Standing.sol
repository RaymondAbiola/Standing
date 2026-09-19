// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Escrow, Hold} from "./base/Escrow.sol";
import {MandateRecord, MandateRegistry} from "./base/MandateRegistry.sol";
import {Permit2Puller} from "./base/Permit2Puller.sol";
import {StandingBook} from "./base/StandingBook.sol";
import {ChargeKind} from "./types/Mandate.sol";

/// Standing: recurring stablecoin payments with recourse.
///
/// A charge pulls from the payer through Permit2 and books the funds into
/// escrow behind an unlock time. The merchant is paid when the window closes.
/// Earned reversal rights, which decide whether a payer may pull a hold back
/// inside that window, land next.
contract Standing is MandateRegistry, Permit2Puller, Escrow, StandingBook {
    /// Placeholder policy. The window becomes a function of merchant history,
    /// shortening as a merchant earns trust, once the merchant registry lands.
    uint64 public constant DEFAULT_WINDOW = 3 days;

    error AboveReversalCeiling(uint256 ceiling);

    event Charged(
        bytes32 indexed id,
        address indexed merchant,
        address indexed payer,
        uint256 holdId,
        address token,
        uint256 amount,
        uint32 chargeCount
    );

    constructor(address permit2, address initialOwner) Permit2Puller(permit2) Escrow(initialOwner) {}

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

    /// Pays the merchant once the window closes and credits the payer's
    /// standing with the settled value.
    ///
    /// Permissionless. The merchant has every reason to call it since that is
    /// how it gets paid, and leaving it open means a stalled integration
    /// cannot trap a payer's funds in escrow.
    ///
    /// The gross amount accrues, not the merchant's net. Standing measures
    /// what the payer has moved cleanly through the system, and the protocol
    /// fee is not the payer's business.
    function finalize(uint256 holdId) external {
        (address payer, uint256 amount) = _finalizeHold(holdId);
        _recordCleanSettlement(payer, amount);
    }

    /// Returns a held charge to the payer before its window closes, and
    /// records the reversal against their standing.
    ///
    /// The ceiling is read against the hold's payer rather than the caller, so
    /// a stranger's attempt still fails on `NotHoldPayer` inside
    /// `_reverseHold` rather than on a ceiling that is not theirs.
    ///
    /// STILL INCOMPLETE. The value ceiling is enforced, but a first-ever
    /// reversal from an address with no history is not yet refused, and an
    /// abusive pattern does not yet suspend the right. Do not ship until both
    /// land.
    function reverse(uint256 holdId) external {
        Hold storage h = _requireReversible(holdId);

        uint256 ceiling = reversalCeiling(h.payer);
        if (h.amount > ceiling) revert AboveReversalCeiling(ceiling);

        address merchant = _executeReversal(holdId);
        _recordReversal(msg.sender, merchant);
    }

    /// Postpaid charges bill for consumption that already happened, so they
    /// carry no reversal right and settle without a window.
    function _windowFor(ChargeKind kind) internal pure returns (uint64) {
        return kind == ChargeKind.Postpaid ? 0 : DEFAULT_WINDOW;
    }
}
