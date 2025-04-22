//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "../Executor.sol";

contract MockExecutor is Executor {
    uint256 public mockChainId;

    constructor(
        address defaultTransporter,
        uint256 _mockChainId
    ) Executor (
        defaultTransporter
    ) {
        mockChainId = _mockChainId;
    }

    function getChainId() public override view returns (uint256 chainId) {
        return mockChainId;
    }
}