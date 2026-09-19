// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Standing} from "../src/Standing.sol";
import {CANONICAL_PERMIT2} from "../src/base/Permit2Puller.sol";

/// Deploys Standing against the canonical Permit2.
///
/// PERMIT2 can be overridden by env var for a chain where the canonical
/// deployment is absent. It is asserted to hold code, because pointing at an
/// empty address would deploy a contract that reverts on every charge.
contract Deploy is Script {
    function run() external returns (Standing standing) {
        address permit2 = vm.envOr("PERMIT2", CANONICAL_PERMIT2);
        require(permit2.code.length > 0, "Deploy: no code at Permit2 address");

        // Owner controls only the fee, within a hard-coded ceiling, and
        // sweeping accrued fees. It can never touch escrowed principal.
        address owner = vm.envOr("OWNER", msg.sender);

        vm.startBroadcast();
        standing = new Standing(permit2, owner);
        vm.stopBroadcast();

        console.log("chainId ", block.chainid);
        console.log("permit2 ", permit2);
        console.log("owner   ", owner);
        console.log("Standing", address(standing));
    }
}
