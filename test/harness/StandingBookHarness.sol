// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {StandingBook} from "../../src/base/StandingBook.sol";

/// StandingBook with its recording entry points exposed, so the state machine
/// can be driven directly instead of through charges and holds. Long
/// histories cost a couple of calls here and a hundred through the full path.
contract StandingBookHarness is StandingBook {
    address public constant DEFAULT_MERCHANT = address(0xDEFA);

    /// Defaults the counterparty so existing tests of the global counters stay
    /// unchanged, with an explicit variant for the per-pair figure.
    function settle(address payer, uint256 amount) external {
        _recordCleanSettlement(payer, DEFAULT_MERCHANT, amount);
    }

    function settleWith(address payer, address merchant, uint256 amount) external {
        _recordCleanSettlement(payer, merchant, amount);
    }

    function reverseAgainst(address payer, address merchant) external {
        _recordReversal(payer, merchant);
    }

    function suspend(address payer, uint32 cycles) external returns (uint32) {
        return _suspend(payer, cycles);
    }
}
