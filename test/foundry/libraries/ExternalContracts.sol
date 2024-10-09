// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;
import {console} from "forge-std/console.sol";

struct OPStackConfig {
    address l1CrossDomainMessenger;
    address l2CrossDomainMessenger;
    uint256 defaultGasLimit;
}

library ExternalContracts {
    function getOpStackConfig(uint256 chainId) internal view returns (OPStackConfig memory) {
        if (chainId == 11155420) {
            return OPStackConfig(
                0x58Cc85b8D04EA49cC6DBd3CbFFd00B4B8D6cb3ef,
                0x4200000000000000000000000000000000000007,
                200_000
            );
        } else if (chainId == 84532) {
            return OPStackConfig(
                0xC34855F4De64F1840e5686e64278da901e261f20,
                0x4200000000000000000000000000000000000007,
                200_000
            );
        } else if (chainId == 42069) {
            return OPStackConfig(
                0x0000000000000000000000000000000000000001,
                0x4200000000000000000000000000000000000007,
                200_000
            );
        }

        console.log("No OPStackConfig for chainId", chainId);
        revert("No OPStackConfig for chainId");
    }
}
