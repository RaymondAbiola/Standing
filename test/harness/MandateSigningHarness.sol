// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {MandateSigning} from "../../src/base/MandateSigning.sol";
import {Mandate} from "../../src/types/Mandate.sol";

contract MandateSigningHarness is MandateSigning {
    function requireValidSignature(Mandate memory m, bytes calldata signature) external view {
        _requireValidSignature(m, signature);
    }
}
