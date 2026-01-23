// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

// This library is inspired by the Arbitrum Outbox state management proposed by shotaronowhere (@shotaro)
// https://github.com/OffchainLabs/nitro/blob/1420d00a0906cfd71448d792f19ade01425d079e/contracts/src/bridge/Outbox.sol

struct Bitmap {
    mapping(uint256 => bytes32) _bitmap;
}

library BitmapLibrary {
    error AlreadyTrue(uint256 index, uint256 chunkIndex, uint256 bitOffset);
    error AlreadyFalse(uint256 index, uint256 chunkIndex, uint256 bitOffset);

    function isTrue(Bitmap storage bitmap, uint256 index) internal view returns (bool) {
        // Split the index into chunk (which 256-bit word) and bit position within that chunk
        // This allows us to efficiently store boolean values using bit packing
        uint256 chunkIndex = index / 256;
        uint256 bitOffset = index % 256;
        bytes32 bitmapChunk = bitmap._bitmap[chunkIndex];
        return _isTrue(bitmapChunk, bitOffset);
    }

    function switchTrue(Bitmap storage bitmap, uint256 index) internal {
        // Calculate which 256-bit storage slot and which bit within that slot
        uint256 chunkIndex = index / 256;
        uint256 bitOffset = index % 256;
        bytes32 bitmapChunk = bitmap._bitmap[chunkIndex];
        
        // Prevent double-setting by checking current state
        if (_isTrue(bitmapChunk, bitOffset)) revert AlreadyTrue(index, chunkIndex, bitOffset);
        
        // Set the bit using bitwise OR with a mask that has only the target bit set
        // (1 << bitOffset) creates a mask with bit at bitOffset position set to 1
        bitmap._bitmap[chunkIndex] = (bitmapChunk | bytes32(1 << bitOffset));
    }

    function switchFalse(Bitmap storage bitmap, uint256 index) internal {
        // Calculate which 256-bit storage slot and which bit within that slot
        uint256 chunkIndex = index / 256;
        uint256 bitOffset = index % 256;
        bytes32 bitmapChunk = bitmap._bitmap[chunkIndex];
        
        // Prevent double-clearing by checking current state
        if (!_isTrue(bitmapChunk, bitOffset)) revert AlreadyFalse(index, chunkIndex, bitOffset);
        
        // Clear the bit using bitwise AND with inverted mask
        // ~bytes32(1 << bitOffset) creates a mask with all bits set except the target bit
        bitmap._bitmap[chunkIndex] = (bitmapChunk & ~bytes32(1 << bitOffset));
    }

    /* Private */
    function _isTrue(bytes32 bitmapChunk, uint256 bitOffset) private pure returns (bool) {
        // Extract the bit at bitOffset position:
        // 1. Right-shift to move target bit to position 0
        // 2. AND with 1 to isolate just that bit
        // 3. Check if result is non-zero (meaning bit was set)
        return ((bitmapChunk >> bitOffset) & bytes32(uint256(1))) != bytes32(0);
    }
}