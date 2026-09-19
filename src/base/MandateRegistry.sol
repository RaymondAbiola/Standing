// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Mandate, MandateLib} from "../types/Mandate.sol";
import {MandateSigning} from "./MandateSigning.sol";

enum MandateStatus {
    None,
    Active,
    Revoked
}

/// Why a charge cannot be taken right now. Exists so the guard and the
/// frontend's probe share one implementation instead of two copies of the
/// same predicates, which would eventually disagree.
enum ChargeBlock {
    None,
    NotLive,
    TooSoon,
    LimitReached,
    AmountZero,
    AmountTooHigh
}

/// Stored lifecycle of one mandate. `epoch` is the payer's revocation epoch at
/// creation: bumping the payer epoch kills every mandate created under an
/// earlier one without touching them individually.
struct MandateRecord {
    Mandate terms;
    MandateStatus status;
    uint32 epoch;
    uint32 chargeCount;
    uint64 lastChargeAt;
    uint64 createdAt;
}

/// Mandate creation, revocation, and charge cadence.
///
/// Terms are stored in full rather than kept offchain and rehashed on every
/// charge. That costs slots once at creation and buys a `charge(bytes32 id)`
/// API plus a dashboard that reads terms straight from the chain with no
/// indexer in the path.
abstract contract MandateRegistry is MandateSigning {
    error ZeroAddress();
    error ZeroAmount();
    error ZeroInterval();
    error BadWindow();
    error MandateExists();
    error UnknownMandate();
    error NotPayer();
    error NotActive();
    error NotLive();
    error TooSoon(uint64 earliestAt);
    error ChargeLimitReached(uint32 maxCharges);
    error AmountExceedsCap(uint256 maxAmount);

    event MandateCreated(
        bytes32 indexed id,
        address indexed payer,
        address indexed merchant,
        address token,
        uint256 maxAmount,
        uint64 minInterval,
        uint64 expiresAt,
        uint32 epoch
    );

    event MandateRevoked(bytes32 indexed id, address indexed payer);

    event PayerEpochBumped(address indexed payer, uint32 epoch);

    mapping(bytes32 id => MandateRecord record) private _mandates;
    mapping(address payer => uint32 epoch) private _payerEpoch;

    /// Permissionless: the payer's signature is the authorisation, so the
    /// merchant can submit it and pay the gas, which is the right incentive
    /// since the merchant is the one who wants the revenue.
    function createMandate(Mandate calldata m, bytes calldata signature) external returns (bytes32 id) {
        if (m.payer == address(0) || m.merchant == address(0) || m.token == address(0)) {
            revert ZeroAddress();
        }
        if (m.maxAmount == 0) revert ZeroAmount();
        if (m.minInterval == 0) revert ZeroInterval();
        if (m.expiresAt <= m.startsAt || m.expiresAt <= block.timestamp) revert BadWindow();

        id = MandateLib.hash(m);

        // Records are never cleared, so a revoked mandate's signature cannot be
        // replayed to recreate it.
        if (_mandates[id].status != MandateStatus.None) revert MandateExists();

        _requireValidSignature(m, signature);

        uint32 epoch = _payerEpoch[m.payer];
        _mandates[id] = MandateRecord({
            terms: m,
            status: MandateStatus.Active,
            epoch: epoch,
            chargeCount: 0,
            lastChargeAt: 0,
            createdAt: uint64(block.timestamp)
        });

        emit MandateCreated(id, m.payer, m.merchant, m.token, m.maxAmount, m.minInterval, m.expiresAt, epoch);
    }

    /// Payer only, and it takes effect in the same block. The merchant cannot
    /// block or delay it.
    function revokeMandate(bytes32 id) external {
        MandateRecord storage r = _mandates[id];
        if (r.status == MandateStatus.None) revert UnknownMandate();
        if (r.status != MandateStatus.Active) revert NotActive();
        if (r.terms.payer != msg.sender) revert NotPayer();

        r.status = MandateStatus.Revoked;
        emit MandateRevoked(id, msg.sender);
    }

    /// The panic button for a compromised treasury: kills every outstanding
    /// mandate at once. The epoch is not part of the signed terms, which is
    /// safe because bumping it only ever withdraws authority, never grants it.
    function revokeAll() external returns (uint32 epoch) {
        epoch = ++_payerEpoch[msg.sender];
        emit PayerEpochBumped(msg.sender, epoch);
    }

    function getMandate(bytes32 id) external view returns (MandateRecord memory) {
        return _mandates[id];
    }

    function payerEpoch(address payer) external view returns (uint32) {
        return _payerEpoch[payer];
    }

    /// True when the mandate is live: active, in window, and created under the
    /// payer's current epoch.
    function isMandateLive(bytes32 id) public view returns (bool) {
        return _isLive(_mandates[id]);
    }

    /// Earliest timestamp at which the next charge may land. Zero for an
    /// unknown mandate. The frontend reads this to show when a merchant can
    /// bill again.
    function nextChargeAt(bytes32 id) public view returns (uint64) {
        MandateRecord storage r = _mandates[id];
        if (r.status == MandateStatus.None) return 0;
        return _nextChargeAt(r);
    }

    /// Charges left under `maxCharges`. Unlimited mandates report uint32 max.
    function chargesRemaining(bytes32 id) external view returns (uint32) {
        MandateRecord storage r = _mandates[id];
        uint32 max = r.terms.maxCharges;
        if (max == 0) return type(uint32).max;
        return r.chargeCount >= max ? 0 : max - r.chargeCount;
    }

    /// Non-reverting probe for the merchant dashboard: can this be billed now.
    function chargeBlocker(bytes32 id, uint256 amount) external view returns (ChargeBlock) {
        return _chargeBlock(_mandates[id], amount);
    }

    function isChargeable(bytes32 id, uint256 amount) external view returns (bool) {
        return _chargeBlock(_mandates[id], amount) == ChargeBlock.None;
    }

    function mandateId(Mandate calldata m) external pure returns (bytes32) {
        return MandateLib.hash(m);
    }

    function _record(bytes32 id) internal view returns (MandateRecord storage) {
        return _mandates[id];
    }

    function _isLive(MandateRecord storage r) internal view returns (bool) {
        return r.status == MandateStatus.Active && r.epoch == _payerEpoch[r.terms.payer]
            && block.timestamp >= r.terms.startsAt && block.timestamp < r.terms.expiresAt;
    }

    /// `minInterval` is a floor on the gap between charges, not a schedule, so
    /// the next window is anchored on the last charge that actually happened
    /// rather than on when it was due. A merchant that bills late shifts its
    /// own schedule later and cannot catch up with a burst, which is the
    /// property the payer signed up for.
    function _nextChargeAt(MandateRecord storage r) internal view returns (uint64) {
        uint64 last = r.lastChargeAt;
        if (last == 0) return r.terms.startsAt;
        unchecked {
            // Saturate. An absurd signed interval should make the mandate
            // permanently unchargeable, not make this view panic.
            uint64 next = last + r.terms.minInterval;
            return next < last ? type(uint64).max : next;
        }
    }

    function _chargeBlock(MandateRecord storage r, uint256 amount) internal view returns (ChargeBlock) {
        if (!_isLive(r)) return ChargeBlock.NotLive;
        if (block.timestamp < _nextChargeAt(r)) return ChargeBlock.TooSoon;

        uint32 max = r.terms.maxCharges;
        if (max != 0 && r.chargeCount >= max) return ChargeBlock.LimitReached;

        if (amount == 0) return ChargeBlock.AmountZero;
        if (amount > r.terms.maxAmount) return ChargeBlock.AmountTooHigh;

        return ChargeBlock.None;
    }

    /// Reverts unless the charge is permitted. Does not mutate: the caller
    /// records the charge once the funds have actually moved.
    function _requireChargeable(bytes32 id, uint256 amount) internal view returns (MandateRecord storage r) {
        r = _mandates[id];
        ChargeBlock b = _chargeBlock(r, amount);
        if (b == ChargeBlock.None) return r;
        if (b == ChargeBlock.NotLive) revert NotLive();
        if (b == ChargeBlock.TooSoon) revert TooSoon(_nextChargeAt(r));
        if (b == ChargeBlock.LimitReached) revert ChargeLimitReached(r.terms.maxCharges);
        if (b == ChargeBlock.AmountZero) revert ZeroAmount();
        revert AmountExceedsCap(r.terms.maxAmount);
    }

    /// Timing and count are recorded when the charge is taken, not when it
    /// settles. Recording at settlement would let a merchant open many charges
    /// inside one interval while they all sat in escrow.
    function _recordCharge(MandateRecord storage r) internal {
        r.lastChargeAt = uint64(block.timestamp);
        r.chargeCount += 1;
    }
}
