// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Escrow, Hold} from "./base/Escrow.sol";
import {MandateRecord, MandateRegistry} from "./base/MandateRegistry.sol";
import {Permit2Puller} from "./base/Permit2Puller.sol";
import {StandingBook} from "./base/StandingBook.sol";
import {ChargeKind} from "./types/Mandate.sol";
import {ReversalBlock} from "./types/Reversal.sol";

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

    error NotVested(uint32 cleanSettlements, uint32 required);
    error ReversalSuspended(uint32 cleanCyclesOwed);
    error AboveReversalCeiling(uint256 ceiling);

    event ReversalSuspensionApplied(address indexed payer, uint32 restoreAtClean);

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
    /// Every condition standing between a hold and a reversal, in the order a
    /// payer most needs to hear them. Non-reverting, and the same predicate
    /// the guard below uses, so the frontend can never show a reversal as
    /// available when the transaction would refuse it.
    function reversalBlocker(uint256 holdId, address caller) public view returns (ReversalBlock) {
        ReversalBlock escrowBlock = _escrowReversalBlock(holdId, caller);
        if (escrowBlock != ReversalBlock.None) return escrowBlock;

        Hold storage h = _peekHold(holdId);

        if (!isVested(h.payer)) return ReversalBlock.NotVested;
        if (isSuspended(h.payer)) return ReversalBlock.Suspended;
        if (h.amount > reversalCeiling(h.payer)) return ReversalBlock.AboveCeiling;

        return ReversalBlock.None;
    }

    function canReverse(uint256 holdId, address caller) external view returns (bool) {
        return reversalBlocker(holdId, caller) == ReversalBlock.None;
    }

    /// Returns a held charge to the payer before its window closes, records
    /// the reversal, and suspends the right if the pattern has become abusive.
    ///
    /// The suspension is evaluated after recording, because whether this
    /// reversal tipped the payer over is exactly what the trigger asks.
    function reverse(uint256 holdId) external {
        Hold storage h = _requireReversible(holdId);
        address payer = h.payer;

        ReversalBlock b = reversalBlocker(holdId, msg.sender);
        if (b == ReversalBlock.NotVested) {
            revert NotVested(cleanSettlementsOf(payer), VESTING_CYCLES);
        }
        if (b == ReversalBlock.Suspended) revert ReversalSuspended(cyclesUntilRestored(payer));
        if (b == ReversalBlock.AboveCeiling) revert AboveReversalCeiling(reversalCeiling(payer));

        address merchant = _executeReversal(holdId);
        _recordReversal(payer, merchant);

        if (isAbusive(payer)) {
            emit ReversalSuspensionApplied(payer, _suspend(payer, SUSPENSION_CYCLES));
        }
    }

    /// Postpaid charges bill for consumption that already happened, so they
    /// carry no reversal right and settle without a window.
    function _windowFor(ChargeKind kind) internal pure returns (uint64) {
        return kind == ChargeKind.Postpaid ? 0 : DEFAULT_WINDOW;
    }
}
