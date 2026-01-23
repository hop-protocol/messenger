// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.9;

library MessengerLib {
    /// @notice Generates a unique message identifier from message parameters
    /// @param bundleNonce The nonce of the bundle containing this message
    /// @param treeIndex The index of the message within the bundle's merkle tree
    /// @param fromChainId The chain ID where the message originated
    /// @param from The address that sent the message
    /// @param toChainId The destination chain ID
    /// @param to The target address on the destination chain
    /// @param data The message calldata
    /// @return The unique message identifier
    function getMessageId(
        bytes32 bundleNonce,
        uint256 treeIndex,
        uint256 fromChainId,
        address from,
        uint256 toChainId,
        address to,
        bytes calldata data
    )
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                bundleNonce,
                treeIndex,
                fromChainId,
                from,
                toChainId,
                to,
                data
            )
        );
    }

    /// @notice Generates a unique bundle identifier from bundle parameters
    /// @param fromChainId The source chain ID
    /// @param toChainId The destination chain ID
    /// @param bundleNonce The bundle nonce
    /// @param bundleRoot The merkle root of all messages in the bundle
    /// @return The unique bundle identifier
    function getBundleId(
        uint256 fromChainId,
        uint256 toChainId,
        bytes32 bundleNonce,
        bytes32 bundleRoot
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                fromChainId,
                toChainId,
                bundleNonce,
                bundleRoot
            )
        );
    }
}
