// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MandateRecord, MandateRegistry} from "../../src/base/MandateRegistry.sol";
import {Permit2Puller} from "../../src/base/Permit2Puller.sol";

/// The charge path as it stands before escrow lands: authorise, record, pull.
///
/// Record before pull is check-effects-interactions, not an arbitrary order.
/// `_pullExact` hands control to the token, so recording afterwards would let
/// a hostile token reenter and take a second charge inside one interval while
/// `lastChargeAt` still held its old value.
contract ChargePathHarness is MandateRegistry, Permit2Puller {
    constructor(address permit2) Permit2Puller(permit2) {}

    function charge(bytes32 id, uint256 amount) external {
        MandateRecord storage r = _requireChargeable(id, amount);
        _recordCharge(r);
        _pullExact(r.terms.token, r.terms.payer, amount);
    }

    /// Deliberately wrong ordering, kept so the reentrancy test can show what
    /// the safe ordering prevents.
    function chargeRecordLast(bytes32 id, uint256 amount) external {
        MandateRecord storage r = _requireChargeable(id, amount);
        _pullExact(r.terms.token, r.terms.payer, amount);
        _recordCharge(r);
    }
}
