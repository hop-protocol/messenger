//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "../Dispatcher.sol";

contract MockDispatcher is Dispatcher {
    uint256 public mockChainId;
    
    constructor(address transporter, uint256 _mockChainId) Dispatcher (transporter) {
        mockChainId = _mockChainId;
    }

    function getChainId() public override view returns (uint256 chainId) {
        return mockChainId;
    }
}