// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

import "@hop-protocol/messenger/contracts/aliases/AliasDeployer.sol";
import "@hop-protocol/messenger/contracts/Dispatcher.sol";

contract CrossChainFees {
    function getFee(uint256 chainId) external view returns (uint256) {
        return 0;
    }
}
