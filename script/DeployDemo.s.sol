// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Standing} from "../src/Standing.sol";
import {CANONICAL_PERMIT2} from "../src/base/Permit2Puller.sol";
import {DemoUSDC} from "./DemoUSDC.sol";

/// Testnet deployment: Standing plus a faucet token to charge in.
///
/// Separate from Deploy.s.sol so the production script never deploys a mock.
contract DeployDemo is Script {
    function run() external returns (Standing standing, DemoUSDC token) {
        address permit2 = vm.envOr("PERMIT2", CANONICAL_PERMIT2);
        require(permit2.code.length > 0, "DeployDemo: no code at Permit2 address");

        address owner = vm.envOr("OWNER", msg.sender);

        vm.startBroadcast();
        standing = new Standing(permit2, owner);
        token = new DemoUSDC();
        vm.stopBroadcast();

        console.log("chainId ", block.chainid);
        console.log("permit2 ", permit2);
        console.log("owner   ", owner);
        console.log("Standing", address(standing));
        console.log("DemoUSDC", address(token));
    }
}
