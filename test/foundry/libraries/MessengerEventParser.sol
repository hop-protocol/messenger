// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/Console.sol";

struct MessageSentEvent {
    uint256 fromChainId;
    bytes32 messageId;
    address from;
    uint256 toChainId;
    address to;
    bytes data;
}

struct MessengerEvents {
    MessageSentEvent[] messageSentEvents;
}

/// @notice - WARNING: Do not switch chains before parsing logs. block.chainid is assigned to the event struct.
library MessengerEventParser {
    function getMessageSentEvents(
        MessengerEvents storage events,
        Vm.Log[] memory logs
    ) internal returns(uint256 startIndex, uint256 numEvents) {
        bytes32 eventSignature = keccak256(abi.encodePacked("MessageSent(bytes32,address,uint256,address,bytes)"));

        startIndex = events.messageSentEvents.length;
        numEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                uint256 fromChainId = block.chainid;
                bytes32 messageId = log.topics[1];
                address from = address(uint160(uint256(log.topics[2])));
                uint256 toChainId = uint256(log.topics[3]);
                (address to, bytes memory data) = abi.decode(log.data, (address, bytes));

                numEvents++;
                events.messageSentEvents.push(MessageSentEvent(
                    fromChainId,
                    messageId,
                    from,
                    toChainId,
                    to,
                    data
                ));
            }
        }

        return (startIndex, numEvents);
    }
}
