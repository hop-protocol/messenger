// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

contract OverridableChainId {
    /// @notice getChainId can be overridden by subclasses if needed for compatibility or testing purposes.
    /// @dev Get the current chainId
    /// @return chainId The current chainId
    function getChainId() public virtual view returns (uint256 chainId) {
        return block.chainid;
    }
}
