// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// Why a reversal cannot happen right now.
///
/// Shared between the vault, which can only answer the first three, and the
/// module that owns standing, which answers the rest. One enum so the
/// frontend's probe and the guard cannot drift into disagreeing.
enum ReversalBlock {
    None,
    HoldNotOpen,
    NotPayer,
    WindowClosed,
    NotVested,
    Suspended,
    AboveCeiling
}
