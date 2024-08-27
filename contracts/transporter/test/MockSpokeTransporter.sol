//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "../SpokeTransporter.sol";

contract MockSpokeTransporter is SpokeTransporter {
    uint256 public mockChainId;

    constructor(
        uint256 l1ChainId,
        uint256 pendingFeeBatchSize,
        uint256 _mockChainId
    )
        SpokeTransporter(l1ChainId, pendingFeeBatchSize)
    {
        mockChainId = _mockChainId;
    }

    function getChainId() public override view returns (uint256 chainId) {
        return mockChainId;
    }
}
