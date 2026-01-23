// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
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