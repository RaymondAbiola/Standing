// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MockERC20} from "./MockERC20.sol";

interface IChargeable {
    function charge(bytes32 id, uint256 amount) external;
    function chargeRecordLast(bytes32 id, uint256 amount) external;
}

/// A token that calls back into the charger during `transferFrom`, which is
/// the shape a malicious mandate token would take.
contract ReenteringToken is MockERC20 {
    IChargeable public target;
    bytes32 public mandate;
    uint256 public amount;
    bool public recordLast;
    bool internal _entered;

    constructor() MockERC20(0) {}

    function arm(IChargeable t, bytes32 id, uint256 a, bool recordLast_) external {
        target = t;
        mandate = id;
        amount = a;
        recordLast = recordLast_;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed < value) revert InsufficientAllowance();
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - value;
        _move(from, to, value);

        if (address(target) != address(0) && !_entered) {
            _entered = true;
            if (recordLast) {
                target.chargeRecordLast(mandate, amount);
            } else {
                target.charge(mandate, amount);
            }
        }
        return true;
    }
}
