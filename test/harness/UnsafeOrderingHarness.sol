// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Escrow} from "../../src/base/Escrow.sol";
import {MandateRecord, MandateRegistry} from "../../src/base/MandateRegistry.sol";
import {Permit2Puller} from "../../src/base/Permit2Puller.sol";

/// Standing's modules wired with the charge steps in the wrong order:
/// the pull happens before the charge is recorded.
///
/// Kept only so the reentrancy tests can show that the ordering in `Standing`
/// is load bearing rather than stylistic. Never deployed.
contract UnsafeOrderingHarness is MandateRegistry, Permit2Puller, Escrow {
    constructor(address permit2, address initialOwner) Permit2Puller(permit2) Escrow(initialOwner) {}

    function chargeRecordLast(bytes32 id, uint256 amount) external returns (uint256 holdId) {
        MandateRecord storage r = _requireChargeable(id, amount);

        _pullExact(r.terms.token, r.terms.payer, amount);
        holdId = _openHold(id, r.terms.payer, r.terms.merchant, r.terms.token, amount, 3 days);

        _recordCharge(r);
    }
}
