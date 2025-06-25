// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

library ExecutorLib {
    /// @notice Executes an arbitrary call to a target address with specified value
    /// @dev This function is used to forward cross-chain messages to their final destination
    /// @param to The target address to call
    /// @param data The calldata to send to the target address
    /// @param value The amount of Ether to send with the call
    /// @return The return data from the successful call
    function execute(
        address to,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        // Execute arbitrary call with provided value
        // This is used to forward cross-chain messages to their final destination
        (bool success, bytes memory res) = payable(to).call{value: value}(data);
        if (!success) {
            // Bubble up the original error message from the failed call
            // This assembly preserves the exact error data without wrapping it
            assembly { 
                revert(add(res,0x20), mload(res)) 
            }
        }
        return res;
    }
}
