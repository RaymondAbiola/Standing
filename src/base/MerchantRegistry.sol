// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// Why a merchant's policy refuses a payer.
enum AcceptanceBlock {
    None,
    StandingTooLow,
    TooManyReversals,
    Suspended
}

/// What a merchant demands of a payer, and how much of an imported ceiling it
/// will honour.
///
/// `set` exists because an unset struct is all zeros, and "requires zero clean
/// settlements, allows zero reversals" would refuse every payer who has ever
/// reversed anything. Absent policy has to mean open to everyone.
///
/// The two cap fields answer a problem the global ceiling cannot. A payer's
/// `cumulativeCleanSettled` records value but not counterparties, so a payer
/// can settle to an address it controls and manufacture a ceiling for the
/// price of gas. Rather than make ceilings per-merchant, which would close the
/// hole by destroying portable reputation entirely, a merchant states how much
/// it will let a stranger reverse before that stranger has settled anything
/// with it:
///
///   until you have settled `trustThreshold` with me, your reversal right
///   here is capped at `reversalCap`, whatever your global ceiling says
///
/// A `trustThreshold` of zero means the global ceiling applies immediately,
/// which keeps the permissive default.
///
/// All five fields share one slot: 1 + 1 + 8 + 32 + 96 + 96 = 234 bits.
struct AcceptancePolicy {
    bool set;
    bool refuseSuspended;
    uint8 maxReversalsInWindow;
    uint32 minCleanSettlements;
    uint96 reversalCap;
    uint96 trustThreshold;
}

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

    /// A cap with no threshold would never bind, because the cap only applies
    /// while the payer is below the threshold. Silently accepting it would let
    /// a merchant believe it was protected when it was not.
    error CapWithoutThreshold();

    event AcceptancePolicySet(
        address indexed merchant,
        uint32 minCleanSettlements,
        uint8 maxReversalsInWindow,
        bool refuseSuspended,
        uint96 reversalCap,
        uint96 trustThreshold
    );

    event MerchantSettled(address indexed merchant, uint32 settlements, uint64 window);
    event MerchantReversedAgainst(address indexed merchant, address indexed payer, uint32 reversals);

    mapping(address merchant => MerchantStanding standing) private _merchants;

    mapping(address merchant => mapping(address payer => bool seen)) private _reversedBy;

    mapping(address merchant => AcceptancePolicy policy) private _policies;

    /// A merchant sets its own terms, for itself only.
    ///
    /// This is the merchant's half of the protection. Standing cannot stop a
    /// payer reversing repeatedly against one merchant, because the dispersion
    /// rule that would catch it is the same rule protecting the customers of a
    /// broken merchant. What a merchant can do is decline the mandate in the
    /// first place, reading a history it can see before it agrees to serve.
    ///
    /// `reversalCap` and `trustThreshold` go further: they bound how much of a
    /// stranger's imported ceiling this merchant will honour before that
    /// stranger has settled anything with it. A threshold of zero keeps the
    /// permissive default of trusting the global ceiling outright.
    function setAcceptancePolicy(
        uint32 minCleanSettlements,
        uint8 maxReversalsInWindow,
        bool refuseSuspended,
        uint96 reversalCap,
        uint96 trustThreshold
    ) external {
        if (reversalCap != 0 && trustThreshold == 0) revert CapWithoutThreshold();

        _policies[msg.sender] = AcceptancePolicy({
            set: true,
            refuseSuspended: refuseSuspended,
            maxReversalsInWindow: maxReversalsInWindow,
            minCleanSettlements: minCleanSettlements,
            reversalCap: reversalCap,
            trustThreshold: trustThreshold
        });

        emit AcceptancePolicySet(
            msg.sender,
            minCleanSettlements,
            maxReversalsInWindow,
            refuseSuspended,
            reversalCap,
            trustThreshold
        );
    }

    /// Reverts to accepting everyone.
    function clearAcceptancePolicy() external {
        delete _policies[msg.sender];
        emit AcceptancePolicySet(msg.sender, 0, 0, false, 0, 0);
    }

    function acceptancePolicyOf(address merchant) public view returns (AcceptancePolicy memory) {
        return _policies[merchant];
    }

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
