// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.19;

import {CrossChainTest} from "./CrossChainTest.sol";

struct Chain {
    string name;
    uint256 chainId;
    string chainAlias;
    string rpcUrl;
}

contract CrossChainScript is CrossChainTest {

    function startBroadcast() internal override {
        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(privateKey);
    }

    function stopBroadcast() internal override {
        vm.stopBroadcast();
    }
}
