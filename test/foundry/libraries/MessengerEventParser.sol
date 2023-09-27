// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/Console.sol";

struct SendMessageEvent {
    uint256 fromChainId;
    bytes32 messageId;
    address from;
    uint256 toChainId;
    address to;
    bytes data;
}

/// @notice - WARNING: Do not switch chains before parsing logs. block.chainid is assigned to the event struct.
library MessengerEventParser {
    function getSendMessageEvents(Vm.Log[] memory logs) internal view returns(SendMessageEvent[] memory) {
        bytes32 eventSignature = keccak256(abi.encodePacked("MessageSent(bytes32,address,uint256,address,bytes)"));

        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                count++;
            }
        }

        SendMessageEvent[] memory sendMessageEvents = new SendMessageEvent[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                sendMessageEvents[j].fromChainId = block.chainid;
                sendMessageEvents[j].messageId = log.topics[1];
                sendMessageEvents[j].from = address(uint160(uint256(log.topics[2])));
                sendMessageEvents[j].toChainId = uint256(log.topics[3]);
                (sendMessageEvents[j].to, sendMessageEvents[j].data) = abi.decode(log.data, (address, bytes));
                j++;
            }
        }

        return sendMessageEvents;
    }
}
