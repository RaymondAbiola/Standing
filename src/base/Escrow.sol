// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

enum HoldStatus {
    None,
    Held,
    Finalized,
    Reversed
}

/// One charge sitting in the reversal window. Fields are copied from the
/// mandate at charge time rather than read back later, so a hold settles on
/// the terms that were in force when it was taken even if the mandate is
/// revoked in the meantime.
struct Hold {
    bytes32 mandateId;
    address payer;
    address merchant;
    address token;
    uint256 amount;
    uint64 unlockAt;
    HoldStatus status;
}

/// The vault side of the window: funds land here on a charge and leave only
/// when the window closes or the payer reverses.
///
/// Holds carry no policy. How long a window lasts is the caller's decision,
/// which is what lets it become a function of merchant history later without
/// touching this module.
abstract contract Escrow {
    /// Caps how long a merchant's money can sit unsettled. A window longer
    /// than this is not a dispute period, it is a merchant financing the
    /// protocol, and no merchant would accept it.
    uint64 public constant MAX_WINDOW = 30 days;

    error WindowTooLong(uint64 maxWindow);
    error UnknownHold();

    event HoldOpened(
        uint256 indexed holdId,
        bytes32 indexed mandateId,
        address indexed merchant,
        address payer,
        address token,
        uint256 amount,
        uint64 unlockAt
    );

    /// Ids start at 1 so that zero reads as absent.
    uint256 private _nextHoldId = 1;

    mapping(uint256 holdId => Hold hold) private _holds;

    /// Sum of open holds per token. The contract's balance of a token must
    /// always cover this, which is the core solvency invariant.
    mapping(address token => uint256 amount) private _totalHeld;

    function getHold(uint256 holdId) external view returns (Hold memory) {
        return _holds[holdId];
    }

    function totalHeld(address token) external view returns (uint256) {
        return _totalHeld[token];
    }

    function nextHoldId() external view returns (uint256) {
        return _nextHoldId;
    }

    /// True once the window has closed. False for an unknown or already
    /// settled hold, so callers cannot act twice on one id.
    function isHoldUnlocked(uint256 holdId) public view returns (bool) {
        Hold storage h = _holds[holdId];
        return h.status == HoldStatus.Held && block.timestamp >= h.unlockAt;
    }

    /// Seconds left before the hold can be finalised. Zero when it is already
    /// unlocked, unknown, or settled.
    function timeUntilUnlock(uint256 holdId) external view returns (uint64) {
        Hold storage h = _holds[holdId];
        if (h.status != HoldStatus.Held || block.timestamp >= h.unlockAt) return 0;
        return h.unlockAt - uint64(block.timestamp);
    }

    /// Books a hold. The funds must already be in this contract: callers pull
    /// first and book second, so a hold never promises money that never
    /// arrived.
    ///
    /// A zero window settles immediately and is how a postpaid charge, which
    /// carries no reversal right, is expressed.
    function _openHold(
        bytes32 mandateId,
        address payer,
        address merchant,
        address token,
        uint256 amount,
        uint64 window
    ) internal returns (uint256 holdId) {
        if (window > MAX_WINDOW) revert WindowTooLong(MAX_WINDOW);

        holdId = _nextHoldId++;
        uint64 unlockAt = uint64(block.timestamp) + window;

        _holds[holdId] = Hold({
            mandateId: mandateId,
            payer: payer,
            merchant: merchant,
            token: token,
            amount: amount,
            unlockAt: unlockAt,
            status: HoldStatus.Held
        });

        _totalHeld[token] += amount;

        emit HoldOpened(holdId, mandateId, merchant, payer, token, amount, unlockAt);
    }

    function _hold(uint256 holdId) internal view returns (Hold storage h) {
        h = _holds[holdId];
        if (h.status == HoldStatus.None) revert UnknownHold();
    }

    function _releaseAccounting(address token, uint256 amount) internal {
        _totalHeld[token] -= amount;
    }
}
