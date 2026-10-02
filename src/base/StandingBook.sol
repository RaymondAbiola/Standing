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

    /// Clean settlements a payer needs before holding any reversal right.
    ///
    /// The ceiling alone does not cover this. A single clean settlement large
    /// enough leaves a ceiling big enough to reverse the next charge outright,
    /// so one payment would buy an immediate right. The ceiling limits how
    /// much can be reversed; this limits how soon, and elapsed cycles are the
    /// one thing a fresh address cannot buy at any price.
    uint32 public constant VESTING_CYCLES = 3;

    /// Reversal rate, as a percentage of the window, above which a pattern
    /// counts as abusive. A reversal is not evidence of abuse on its own, so
    /// the trigger is a rate rather than a count.
    uint8 public constant ABUSE_RATE_PERCENT = 20;

    /// Outcomes needed before a rate means anything. Two reversals out of
    /// three is a 67 percent rate and tells you nothing.
    uint8 public constant MIN_SAMPLE = 5;

    /// Distinct merchants a payer must have reversed against before a high
    /// rate is read as their behaviour.
    ///
    /// This is what keeps the trigger from punishing the customer of a broken
    /// merchant. Reversals concentrated on one counterparty are evidence about
    /// that counterparty; the same rate spread across unrelated merchants is
    /// evidence about the payer. Dispersion is lifetime rather than windowed,
    /// because having reversed against several unrelated merchants at any
    /// point is what makes a recent spike look like a habit.
    uint32 public constant DISPERSION_THRESHOLD = 3;

    /// Clean settlements needed to lift a suspension.
    uint32 public constant SUSPENSION_CYCLES = 3;

    event StandingSettled(address indexed payer, uint256 amount, uint256 cumulativeCleanSettled);
    event StandingReversed(address indexed payer, address indexed merchant, uint32 distinctMerchants);

    mapping(address payer => PayerStanding standing) private _standing;

    /// Merchants a payer has reversed against, so dispersion is counted once
    /// per merchant rather than once per reversal.
    mapping(address payer => mapping(address merchant => bool seen)) private _reversedAgainst;

    /// Value a payer has settled cleanly with each merchant.
    ///
    /// The global `cumulativeCleanSettled` says nothing about counterparties,
    /// which makes it forgeable: a payer can settle to an address it controls
    /// and build a ceiling for the price of gas. This per-pair figure is what
    /// lets a merchant decide how much of an imported ceiling to honour before
    /// the payer has settled anything with it.
    mapping(address payer => mapping(address merchant => uint256 value)) private _cleanSettledWith;

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

    /// Whether this payer's recent pattern trips the abuse trigger. All three
    /// conditions must hold: enough sample, a rate above the threshold, and
    /// reversals spread across enough merchants.
    function isAbusive(address payer) public view returns (bool) {
        uint8 n = sampleSize(payer);
        if (n < MIN_SAMPLE) return false;
        if (_standing[payer].distinctMerchantsReversed < DISPERSION_THRESHOLD) return false;

        return uint256(reversalsInWindow(payer)) * 100 > uint256(n) * ABUSE_RATE_PERCENT;
    }

    function isSuspended(address payer) public view returns (bool) {
        return _isSuspended(payer);
    }

    /// Clean settlements still owed before the right comes back.
    function cyclesUntilRestored(address payer) public view returns (uint32) {
        PayerStanding storage s = _standing[payer];
        return s.cleanSettlements >= s.restoreAtClean ? 0 : s.restoreAtClean - s.cleanSettlements;
    }

    /// Value this payer has settled cleanly with this merchant specifically.
    function cleanSettledWith(address payer, address merchant) public view returns (uint256) {
        return _cleanSettledWith[payer][merchant];
    }

    function cleanSettlementsOf(address payer) public view returns (uint32) {
        return _standing[payer].cleanSettlements;
    }

    /// Whether this payer holds any reversal right at all yet.
    function isVested(address payer) public view returns (bool) {
        return cleanSettlementsOf(payer) >= VESTING_CYCLES;
    }

    /// Clean settlements still needed before the right activates.
    function cyclesUntilVested(address payer) external view returns (uint32) {
        uint32 clean = _standing[payer].cleanSettlements;
        return clean >= VESTING_CYCLES ? 0 : VESTING_CYCLES - clean;
    }

    /// The largest single hold this payer may reverse right now.
    function reversalCeiling(address payer) public view returns (uint256) {
        return _standing[payer].cumulativeCleanSettled / CEILING_DIVISOR;
    }

    function hasReversedAgainst(address payer, address merchant) external view returns (bool) {
        return _reversedAgainst[payer][merchant];
    }

    function _recordCleanSettlement(address payer, address merchant, uint256 amount) internal {
        PayerStanding storage s = _standing[payer];

        s.cumulativeCleanSettled += amount;
        s.cleanSettlements += 1;
        _cleanSettledWith[payer][merchant] += amount;
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
    function _suspend(address payer, uint32 cleanCyclesRequired) internal returns (uint32 restoreAt) {
        PayerStanding storage s = _standing[payer];
        restoreAt = s.cleanSettlements + cleanCyclesRequired;
        s.restoreAtClean = restoreAt;
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
