// SPDX-License-Identifier: UNLICENSED
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
        uint256 privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.stopBroadcast();
    }
}
