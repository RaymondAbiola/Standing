// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Escrow, Hold} from "./base/Escrow.sol";
import {MandateRecord, MandateRegistry} from "./base/MandateRegistry.sol";
import {AcceptanceBlock, AcceptancePolicy, MerchantRegistry} from "./base/MerchantRegistry.sol";
import {Permit2Puller} from "./base/Permit2Puller.sol";
import {StandingBook} from "./base/StandingBook.sol";
import {ChargeKind, Mandate} from "./types/Mandate.sol";
import {ReversalBlock} from "./types/Reversal.sol";

/// Standing: recurring stablecoin payments with recourse.
///
/// A charge pulls from the payer through Permit2 and books the funds into
/// escrow behind an unlock time. The merchant is paid when the window closes.
/// Earned reversal rights, which decide whether a payer may pull a hold back
/// inside that window, land next.
contract Standing is MandateRegistry, Permit2Puller, Escrow, StandingBook, MerchantRegistry {
    error PayerStandingTooLow(uint32 cleanSettlements, uint32 required);
    error PayerTooManyReversals(uint8 inWindow, uint8 allowed);
    error PayerSuspendedByPolicy();
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

    /// Anyone may submit a signed mandate, subject to the merchant's own
    /// acceptance policy.
    ///
    /// The policy is checked here and never again. A merchant that later
    /// dislikes a payer simply stops calling `charge`, which it controls, so
    /// re-checking on every charge would only add a way to strand a payer
    /// mid-subscription without giving the merchant anything it lacks.
    function createMandate(Mandate calldata m, bytes calldata signature) external returns (bytes32) {
        AcceptanceBlock b = acceptanceBlocker(m.merchant, m.payer);

        if (b == AcceptanceBlock.StandingTooLow) {
            revert PayerStandingTooLow(
                cleanSettlementsOf(m.payer), acceptancePolicyOf(m.merchant).minCleanSettlements
            );
        }
        if (b == AcceptanceBlock.TooManyReversals) {
            revert PayerTooManyReversals(
                reversalsInWindow(m.payer), acceptancePolicyOf(m.merchant).maxReversalsInWindow
            );
        }
        if (b == AcceptanceBlock.Suspended) revert PayerSuspendedByPolicy();

        return _createMandate(m, signature);
    }

    /// Why this merchant's policy would refuse this payer. The same predicate
    /// the guard above uses, so a merchant dashboard cannot show a payer as
    /// acceptable when creation would refuse them.
    function acceptanceBlocker(address merchant, address payer) public view returns (AcceptanceBlock) {
        AcceptancePolicy memory p = acceptancePolicyOf(merchant);
        if (!p.set) return AcceptanceBlock.None;

        if (cleanSettlementsOf(payer) < p.minCleanSettlements) return AcceptanceBlock.StandingTooLow;
        if (reversalsInWindow(payer) > p.maxReversalsInWindow) return AcceptanceBlock.TooManyReversals;
        if (p.refuseSuspended && isSuspended(payer)) return AcceptanceBlock.Suspended;

        return AcceptanceBlock.None;
    }

    function wouldAccept(address merchant, address payer) external view returns (bool) {
        return acceptanceBlocker(merchant, payer) == AcceptanceBlock.None;
    }

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
        uint64 window = _windowFor(r.terms.chargeKind, merchant);

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
        address merchant = _peekHold(holdId).merchant;
        (address payer, uint256 amount) = _finalizeHold(holdId);

        _recordCleanSettlement(payer, amount);
        _recordMerchantSettlement(merchant);
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
        _recordMerchantReversal(merchant, payer);

        if (isAbusive(payer)) {
            emit ReversalSuspensionApplied(payer, _suspend(payer, SUSPENSION_CYCLES));
        }
    }

    /// Postpaid charges bill for consumption that already happened, so they
    /// carry no reversal right and settle without a window. Everything else
    /// waits as long as the merchant's own record says it should.
    function _windowFor(ChargeKind kind, address merchant) internal view returns (uint64) {
        return kind == ChargeKind.Postpaid ? 0 : windowFor(merchant);
    }
}
