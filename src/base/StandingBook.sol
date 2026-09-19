// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// What a payer has built up. One slot for the running total, one for every
/// counter, so a settlement costs two writes.
struct PayerStanding {
    /// Sum of settlements that completed without reversal. The reversal
    /// ceiling is derived from this, so cheap history cannot unlock expensive
    /// theft.
    uint256 cumulativeCleanSettled;
    /// Count of clean settlements. Vesting and suspension recovery are both
    /// measured against this rather than against elapsed time.
    uint32 cleanSettlements;
    uint32 reversals;
    /// How many distinct merchants this payer has reversed against. Reversals
    /// concentrated on one merchant indict the merchant; reversals spread thin
    /// across unrelated merchants indict the payer.
    uint32 distinctMerchantsReversed;
    /// Suspended while `cleanSettlements` is below this. Zero means never
    /// suspended.
    uint32 restoreAtClean;
    /// Rolling outcome history, bit 0 the most recent. Set means reversed.
    uint32 recentOutcomes;
    /// Meaningful bits in `recentOutcomes`, capped at 32.
    uint8 recentCount;
}

/// Records what payers do and answers what their standing is.
///
/// Counting and the derived reads live here together, so the frontend has one
/// place to ask about a payer. Enforcement does not: whether a given payer may
/// reverse a given hold is decided by the module that owns both the standing
/// and the escrow, which keeps this testable on its own.
abstract contract StandingBook {
    /// Outcomes considered when judging a reversal rate. Ten is long enough
    /// to be meaningful and short enough that a payer can recover from a bad
    /// run rather than carrying it forever.
    uint8 public constant RATE_WINDOW = 10;

    /// A payer may reverse a hold worth at most this fraction of what they
    /// have settled cleanly.
    ///
    /// This is what closes reputation laundering. Without it, vesting cheaply
    /// on a dollar-a-month service would unlock the right to reverse an
    /// enterprise plan, so the cheapest possible history would gate the most
    /// expensive possible theft. Tying the ceiling to accumulated value means
    /// the asset a payer destroys by abusing the right scales with the size of
    /// the theft it enables.
    uint256 public constant CEILING_DIVISOR = 3;

    event StandingSettled(address indexed payer, uint256 amount, uint256 cumulativeCleanSettled);
    event StandingReversed(address indexed payer, address indexed merchant, uint32 distinctMerchants);

    mapping(address payer => PayerStanding standing) private _standing;

    /// Merchants a payer has reversed against, so dispersion is counted once
    /// per merchant rather than once per reversal.
    mapping(address payer => mapping(address merchant => bool seen)) private _reversedAgainst;

    function standingOf(address payer) external view returns (PayerStanding memory) {
        return _standing[payer];
    }

    /// Reversals among the last `RATE_WINDOW` outcomes.
    function reversalsInWindow(address payer) public view returns (uint8 count) {
        PayerStanding storage s = _standing[payer];
        uint8 n = s.recentCount < RATE_WINDOW ? s.recentCount : RATE_WINDOW;
        uint32 bits = s.recentOutcomes;

        for (uint8 i; i < n; ++i) {
            if ((bits >> i) & 1 == 1) count += 1;
        }
    }

    /// Outcomes on record, capped at `RATE_WINDOW`. The denominator for a
    /// rate, and the sample size a judgement needs before it means anything.
    function sampleSize(address payer) public view returns (uint8) {
        uint8 n = _standing[payer].recentCount;
        return n < RATE_WINDOW ? n : RATE_WINDOW;
    }

    /// The largest single hold this payer may reverse right now.
    function reversalCeiling(address payer) public view returns (uint256) {
        return _standing[payer].cumulativeCleanSettled / CEILING_DIVISOR;
    }

    function hasReversedAgainst(address payer, address merchant) external view returns (bool) {
        return _reversedAgainst[payer][merchant];
    }

    function _recordCleanSettlement(address payer, uint256 amount) internal {
        PayerStanding storage s = _standing[payer];

        s.cumulativeCleanSettled += amount;
        s.cleanSettlements += 1;
        _pushOutcome(s, false);

        emit StandingSettled(payer, amount, s.cumulativeCleanSettled);
    }

    function _recordReversal(address payer, address merchant) internal {
        PayerStanding storage s = _standing[payer];

        s.reversals += 1;
        if (!_reversedAgainst[payer][merchant]) {
            _reversedAgainst[payer][merchant] = true;
            s.distinctMerchantsReversed += 1;
        }
        _pushOutcome(s, true);

        emit StandingReversed(payer, merchant, s.distinctMerchantsReversed);
    }

    /// Suspension is served in clean settlements, not in seconds. A payer who
    /// abused the right earns it back by paying cleanly, and cannot simply
    /// wait out a timer while doing nothing.
    function _suspend(address payer, uint32 cleanCyclesRequired) internal {
        PayerStanding storage s = _standing[payer];
        s.restoreAtClean = s.cleanSettlements + cleanCyclesRequired;
    }

    function _isSuspended(address payer) internal view returns (bool) {
        PayerStanding storage s = _standing[payer];
        return s.cleanSettlements < s.restoreAtClean;
    }

    function _pushOutcome(PayerStanding storage s, bool reversed) private {
        s.recentOutcomes = (s.recentOutcomes << 1) | (reversed ? 1 : 0);
        if (s.recentCount < 32) s.recentCount += 1;
    }
}
