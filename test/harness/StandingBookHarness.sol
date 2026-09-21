// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StandingBook} from "../../src/base/StandingBook.sol";

/// StandingBook with its recording entry points exposed, so the state machine
/// can be driven directly instead of through charges and holds. Long
/// histories cost a couple of calls here and a hundred through the full path.
contract StandingBookHarness is StandingBook {
    function settle(address payer, uint256 amount) external {
        _recordCleanSettlement(payer, amount);
    }

    function reverseAgainst(address payer, address merchant) external {
        _recordReversal(payer, merchant);
    }

    function suspend(address payer, uint32 cycles) external returns (uint32) {
        return _suspend(payer, cycles);
    }
}
