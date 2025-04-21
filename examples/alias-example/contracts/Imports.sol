// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@hop-protocol/messenger/contracts/aliases/AliasDeployer.sol";
import "@hop-protocol/messenger/contracts/Dispatcher.sol";

contract CrossChainFees {
    function getFee(uint256 chainId) external view returns (uint256) {
        return 0;
    }
}
