// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MandateRegistry} from "../../src/base/MandateRegistry.sol";
import {Mandate} from "../../src/types/Mandate.sol";

contract MandateRegistryHarness is MandateRegistry {
    /// Creation is internal now, with the external entry point on Standing
    /// where the merchant policy is applied. This wrapper keeps the registry
    /// testable without a policy in the way.
    function createMandate(Mandate calldata m, bytes calldata signature) external returns (bytes32) {
        return _createMandate(m, signature);
    }
}
