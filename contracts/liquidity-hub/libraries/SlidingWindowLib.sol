//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

struct SlidingWindow {
    mapping(uint256 => uint256) value;
}

library SlidingWindowLib {
    uint256 constant SLOT_SIZE = 1 hours;

    function add(SlidingWindow storage window, uint256 timestamp, uint256 amount) internal {
        uint256 slot = slotForTimestamp(timestamp);
        window.value[slot] += amount;
    }

    function sub(SlidingWindow storage window, uint256 timestamp, uint256 amount) internal {
        uint256 slot = slotForTimestamp(timestamp);
        window.value[slot] -= amount;
    }

    function addToSlot(SlidingWindow storage window, uint256 slot, uint256 amount) internal {
        window.value[slot] += amount;
    }

    function subtractFromSlot(SlidingWindow storage window, uint256 slot, uint256 amount) internal {
        window.value[slot] += amount;
    }

    function set(SlidingWindow storage window, uint256 timestamp, uint256 amount) internal {
        uint256 slot = slotForTimestamp(timestamp);
        window.value[slot] = amount;
    }

    function get(SlidingWindow storage window, uint256 timestamp) internal view returns (uint256) {
        uint256 slot = slotForTimestamp(timestamp);
        return window.value[slot];
    }

    function totalSince(SlidingWindow storage window, uint256 timestamp) internal view returns (uint256) {
        uint256 startSlot = slotForTimestamp(timestamp);
        uint256 currentSlot = slotForTimestamp(block.timestamp);
        require(currentSlot >= startSlot, "SlidingWindowLib: timestamp is in the future");

        uint256 total = 0;
        for (uint256 i = startSlot; i <= currentSlot; i++) {
            total += window.value[i];
        }

        return total;
    }

    function slotForTimestamp(uint256 timestamp) internal pure returns (uint256) {
        return timestamp / SLOT_SIZE;
    }
}