// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";

import {Permit2Puller} from "../../src/base/Permit2Puller.sol";
import {IAllowanceTransfer} from "../../src/interfaces/IAllowanceTransfer.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract PullerHarness is Permit2Puller {
    constructor(address permit2) Permit2Puller(permit2) {}

    function pull(address token, address from, uint256 amount) external {
        _pullExact(token, from, amount);
    }
}

/// Runs against the deployed Permit2, not a mock, because the allowance
/// decrement and the expiry are behaviours of the real contract and a mock
/// only proves that the mock agrees with itself.
///
/// Skipped unless ARBITRUM_SEPOLIA_RPC_URL is set, so the default suite stays
/// hermetic and CI does not depend on a public rate-limited endpoint.
contract Permit2ForkTest is Test {
    IAllowanceTransfer internal constant PERMIT2 =
        IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    PullerHarness internal puller;
    address internal payer = makeAddr("payer");

    function setUp() public {
        string memory url = vm.envOr("ARBITRUM_SEPOLIA_RPC_URL", string(""));
        if (bytes(url).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(url);
        assertGt(address(PERMIT2).code.length, 0, "Permit2 not deployed on this fork");
        puller = new PullerHarness(address(PERMIT2));
    }

    function _armed(uint256 feeBps, uint160 allow) internal returns (MockERC20 token) {
        token = new MockERC20(feeBps);
        token.mint(payer, 1000e6);
        vm.startPrank(payer);
        token.approve(address(PERMIT2), type(uint256).max);
        PERMIT2.approve(address(token), address(puller), allow, uint48(block.timestamp + 365 days));
        vm.stopPrank();
    }

    function test_realPermit2PullsAndDecrements() public {
        MockERC20 token = _armed(0, 100e6);

        puller.pull(address(token), payer, 30e6);

        assertEq(token.balanceOf(address(puller)), 30e6);
        assertEq(token.balanceOf(payer), 970e6);

        (uint160 remaining,,) = puller.permit2Allowance(payer, address(token));
        assertEq(remaining, 70e6);
    }

    function test_realPermit2RejectsAfterExpiry() public {
        MockERC20 token = _armed(0, 100e6);
        vm.warp(block.timestamp + 366 days);

        vm.expectRevert();
        puller.pull(address(token), payer, 1e6);
    }

    function test_realPermit2RejectsOverAllowance() public {
        MockERC20 token = _armed(0, 30e6);
        puller.pull(address(token), payer, 30e6);

        vm.expectRevert();
        puller.pull(address(token), payer, 1);
    }

    function test_feeOnTransferRejectedAgainstRealPermit2() public {
        MockERC20 token = _armed(100, 100e6);

        vm.expectRevert(Permit2Puller.InexactTransfer.selector);
        puller.pull(address(token), payer, 30e6);
    }
}
