// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// What a merchant has built up. The mirror of payer standing, read in the
/// opposite direction: a payer earns the right to reverse, a merchant earns
/// faster access to its own revenue.
struct MerchantStanding {
    uint32 settlements;
    uint32 reversals;
    /// Distinct payers who have reversed against this merchant. The same
    /// dispersion idea as on the payer side: many payers reversing is evidence
    /// about the merchant, one payer doing it repeatedly is not.
    uint32 distinctPayersReversed;
}

/// Sets how long a merchant's money waits before it can be claimed.
///
/// A fixed hold is the most likely reason a merchant declines this outright,
/// because it is a real cashflow cost with nothing offered in return. So the
/// hold is priced rather than fixed: a merchant with a long clean record waits
/// hours, a merchant nobody has transacted with waits days, and a merchant
/// whose charges keep getting reversed stays at the maximum however much
/// volume it has.
///
/// Tiers rather than a curve, because a merchant needs to be able to read this
/// and know what it will get. Changing the tiers means a redeploy, which keeps
/// the owner's powers to exactly two: the fee, within its cap, and sweeping
/// fees.
abstract contract MerchantRegistry {
    /// What an unknown merchant waits.
    uint64 public constant MAX_MERCHANT_WINDOW = 5 days;

    /// The floor, however long the record.
    uint64 public constant MIN_MERCHANT_WINDOW = 2 hours;

    /// Reversal rate, as a percentage of settlements, above which a merchant
    /// keeps the maximum window regardless of volume.
    ///
    /// Tighter than the payer-side threshold. A reversal against a merchant is
    /// a customer taking their money back, and a merchant earning those at
    /// scale should not also be holding everyone else's funds briefly.
    uint8 public constant MERCHANT_RATE_PERCENT = 10;

    /// Settlements before that rate is read as meaningful.
    uint32 public constant MERCHANT_MIN_SAMPLE = 20;

    event MerchantSettled(address indexed merchant, uint32 settlements, uint64 window);
    event MerchantReversedAgainst(address indexed merchant, address indexed payer, uint32 reversals);

    mapping(address merchant => MerchantStanding standing) private _merchants;

    mapping(address merchant => mapping(address payer => bool seen)) private _reversedBy;

    function merchantStandingOf(address merchant) external view returns (MerchantStanding memory) {
        return _merchants[merchant];
    }

    function hasBeenReversedBy(address merchant, address payer) external view returns (bool) {
        return _reversedBy[merchant][payer];
    }

    /// Whether this merchant's reversal rate has it pinned at the maximum.
    function isMerchantFlagged(address merchant) public view returns (bool) {
        MerchantStanding storage m = _merchants[merchant];
        if (m.settlements < MERCHANT_MIN_SAMPLE) return false;
        return uint256(m.reversals) * 100 > uint256(m.settlements) * MERCHANT_RATE_PERCENT;
    }

    /// How long a charge to this merchant will be held.
    function windowFor(address merchant) public view returns (uint64) {
        if (isMerchantFlagged(merchant)) return MAX_MERCHANT_WINDOW;

        uint32 settled = _merchants[merchant].settlements;
        if (settled >= 1000) return MIN_MERCHANT_WINDOW;
        if (settled >= 100) return 12 hours;
        if (settled >= 10) return 2 days;
        return MAX_MERCHANT_WINDOW;
    }

    function _recordMerchantSettlement(address merchant) internal {
        MerchantStanding storage m = _merchants[merchant];
        m.settlements += 1;
        emit MerchantSettled(merchant, m.settlements, windowFor(merchant));
    }

    function _recordMerchantReversal(address merchant, address payer) internal {
        MerchantStanding storage m = _merchants[merchant];
        m.reversals += 1;
        if (!_reversedBy[merchant][payer]) {
            _reversedBy[merchant][payer] = true;
            m.distinctPayersReversed += 1;
        }
        emit MerchantReversedAgainst(merchant, payer, m.reversals);
    }
}
