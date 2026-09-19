// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable, Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

enum HoldStatus {
    None,
    Held,
    Finalized,
    Reversed
}

/// One charge sitting in the reversal window. Fields are copied from the
/// mandate at charge time rather than read back later, so a hold settles on
/// the terms that were in force when it was taken even if the mandate is
/// revoked in the meantime. `feeBps` is snapshotted for the same reason.
struct Hold {
    bytes32 mandateId;
    address payer;
    address merchant;
    address token;
    uint256 amount;
    uint64 unlockAt;
    HoldStatus status;
    uint16 feeBps;
}

/// The vault side of the window: funds land here on a charge and leave only
/// when the window closes or the payer reverses.
///
/// Holds carry no policy. How long a window lasts is the caller's decision,
/// which is what lets it become a function of merchant history later without
/// touching this module.
abstract contract Escrow is Ownable2Step {
    using SafeERC20 for IERC20;

    /// Caps how long a merchant's money can sit unsettled. A window longer
    /// than this is not a dispute period, it is a merchant financing the
    /// protocol, and no merchant would accept it.
    uint64 public constant MAX_WINDOW = 30 days;

    /// Hard ceiling on the protocol fee, enforced in code rather than left to
    /// the owner's discretion. A fee the owner can raise without limit is a
    /// reason not to integrate.
    uint16 public constant MAX_FEE_BPS = 100;

    uint256 private constant BPS_DENOMINATOR = 10_000;

    error WindowTooLong(uint64 maxWindow);
    error UnknownHold();
    error HoldNotOpen();
    error StillLocked(uint64 unlockAt);
    error NotHoldPayer();
    error WindowClosed(uint64 unlockAt);
    error FeeTooHigh(uint16 maxFeeBps);
    error ZeroRecipient();

    event HoldReversed(uint256 indexed holdId, address indexed payer, address token, uint256 amount);

    event HoldFinalized(
        uint256 indexed holdId, address indexed merchant, address token, uint256 paid, uint256 fee
    );

    event HoldOpened(
        uint256 indexed holdId,
        bytes32 indexed mandateId,
        address indexed merchant,
        address payer,
        address token,
        uint256 amount,
        uint64 unlockAt
    );

    event FeeBpsUpdated(uint16 feeBps);
    event FeesSwept(address indexed token, address indexed to, uint256 amount);

    /// Ids start at 1 so that zero reads as absent.
    uint256 private _nextHoldId = 1;

    uint16 private _feeBps;

    mapping(uint256 holdId => Hold hold) private _holds;

    /// Sum of open holds per token. The contract's balance of a token must
    /// always cover this plus accrued fees, which is the solvency invariant.
    mapping(address token => uint256 amount) private _totalHeld;

    /// Fees taken at settlement, held here until swept. Tracked apart from
    /// `_totalHeld` so a sweep can never reach into escrowed principal.
    mapping(address token => uint256 amount) private _accruedFees;

    constructor(address initialOwner) Ownable(initialOwner) {}

    function getHold(uint256 holdId) external view returns (Hold memory) {
        return _holds[holdId];
    }

    function totalHeld(address token) external view returns (uint256) {
        return _totalHeld[token];
    }

    function accruedFees(address token) external view returns (uint256) {
        return _accruedFees[token];
    }

    function nextHoldId() external view returns (uint256) {
        return _nextHoldId;
    }

    function feeBps() external view returns (uint16) {
        return _feeBps;
    }

    /// Applies to charges taken from here on. Open holds keep the rate they
    /// were booked at, so raising the fee cannot reach money already in
    /// escrow.
    function setFeeBps(uint16 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh(MAX_FEE_BPS);
        _feeBps = newFeeBps;
        emit FeeBpsUpdated(newFeeBps);
    }

    function sweepFees(address token, address to) external onlyOwner returns (uint256 amount) {
        if (to == address(0)) revert ZeroRecipient();

        amount = _accruedFees[token];
        _accruedFees[token] = 0;

        IERC20(token).safeTransfer(to, amount);
        emit FeesSwept(token, to, amount);
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

    /// Pays the merchant once the window has closed, net of the fee the hold
    /// was booked at. Returns what the caller needs to record the outcome.
    ///
    /// Internal, with the external entry point one layer up. The vault knows
    /// how to move money and nothing about reputation, so the module that
    /// owns both does the sequencing.
    ///
    /// Status and accounting are written before the transfer. A hostile token
    /// reentering here finds the hold already marked Finalized and reverts.
    function _finalizeHold(uint256 holdId) internal returns (address payer, uint256 amount) {
        Hold storage h = _hold(holdId);
        if (h.status != HoldStatus.Held) revert HoldNotOpen();
        if (block.timestamp < h.unlockAt) revert StillLocked(h.unlockAt);

        address token = h.token;
        address merchant = h.merchant;
        payer = h.payer;
        amount = h.amount;
        uint256 fee = (amount * h.feeBps) / BPS_DENOMINATOR;
        uint256 paid = amount - fee;

        h.status = HoldStatus.Finalized;
        _totalHeld[token] -= amount;
        if (fee != 0) _accruedFees[token] += fee;

        IERC20(token).safeTransfer(merchant, paid);

        emit HoldFinalized(holdId, merchant, token, paid, fee);
    }

    /// Returns a held charge to the payer before its window closes. Returns
    /// the merchant it was owed to, which the caller needs for dispersion.
    ///
    /// Payer only. Unlike finalize, this cannot be permissionless: it is the
    /// payer's remedy and nobody else's, and a third party able to trigger it
    /// could grief a merchant at will.
    ///
    /// The payer is made whole with no fee deducted. Charging for a reversal
    /// would price the remedy, and a remedy that costs money to use is not
    /// one most payers would ever exercise.
    ///
    /// Postpaid charges need no special case here. They settle with a zero
    /// window, so they are already past `unlockAt` when the hold is booked and
    /// the window check refuses them.
    ///
    /// UNCONDITIONAL FOR NOW. A vested, value-capped reversal right is what
    /// stops this from being a free option the payer can exercise every cycle,
    /// and it is checked here once the standing book lands. Do not ship
    /// without it.
    function _reverseHold(uint256 holdId) internal returns (address merchant) {
        Hold storage h = _hold(holdId);
        if (h.status != HoldStatus.Held) revert HoldNotOpen();
        if (msg.sender != h.payer) revert NotHoldPayer();
        if (block.timestamp >= h.unlockAt) revert WindowClosed(h.unlockAt);

        address token = h.token;
        uint256 amount = h.amount;
        merchant = h.merchant;

        h.status = HoldStatus.Reversed;
        _totalHeld[token] -= amount;

        IERC20(token).safeTransfer(msg.sender, amount);

        emit HoldReversed(holdId, msg.sender, token, amount);
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
            status: HoldStatus.Held,
            feeBps: _feeBps
        });

        _totalHeld[token] += amount;

        emit HoldOpened(holdId, mandateId, merchant, payer, token, amount, unlockAt);
    }

    function _hold(uint256 holdId) internal view returns (Hold storage h) {
        h = _holds[holdId];
        if (h.status == HoldStatus.None) revert UnknownHold();
    }
}
