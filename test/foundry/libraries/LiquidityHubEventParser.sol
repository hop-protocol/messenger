// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/Console.sol";

struct TransferSentEvent{
    uint256 chainId;
    uint256 timestamp;
    bytes32 pathId;
    bytes32 checkpointId;
    address to;
    uint256 amount;
    uint256 minAmountOut;
    uint256 totalSent;
    uint256 nonce;
    bytes32 attestedCheckpoint;
}

struct TransferBondedEvent{
    uint256 chainId;
    uint256 timestamp;
    bytes32 claimId;
    bytes32 pathId;
    address to;
    uint256 amount;
    uint256 minAmountOut;
    uint256 totalSent;
}

struct LiquidityHubEvents {
    TransferSentEvent[] transferSentEvents;
    TransferBondedEvent[] transferBondedEvents;
}

/// @notice - WARNING: Do not switch chains before parsing logs. block.chainid is assigned to the event struct.
library LiquidityHubEventParser {
    function getTransferSentEvents(
        LiquidityHubEvents storage events,
        Vm.Log[] memory logs
    )
        internal
        returns(uint256 startIndex, uint256 numEvents)
    {
        bytes32 eventSignature = keccak256(abi.encodePacked("TransferSent(bytes32,bytes32,address,uint256,uint256,uint256,uint256,bytes32)"));

        startIndex = events.transferSentEvents.length;
        numEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {

            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                (
                    uint256 amount,
                    uint256 minAmountOut,
                    uint256 totalSent,
                    uint256 nonce,
                    bytes32 attestedCheckpoint
                ) = abi.decode(log.data, (uint256,uint256,uint256,uint256,bytes32));

                numEvents++;
                events.transferSentEvents.push(TransferSentEvent(
                    block.chainid,
                    block.timestamp,
                    log.topics[1],
                    log.topics[2],
                    address(uint160(uint256(log.topics[3]))),
                    amount,
                    minAmountOut,
                    totalSent,
                    nonce,
                    attestedCheckpoint
                ));
            }
        }
    }

    function getTransferBondedEvents(
        LiquidityHubEvents storage events,
        Vm.Log[] memory logs
    )
        internal
        returns(uint256 startIndex, uint256 numEvents)
    {
        bytes32 eventSignature = keccak256(abi.encodePacked("TransferBonded(bytes32,bytes32,address,uint256,uint256,uint256)"));

        startIndex = events.transferBondedEvents.length;
        numEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                (
                    uint256 amount,
                    uint256 minAmountOut,
                    uint256 totalSent
                ) = abi.decode(log.data, (uint256, uint256, uint256));

                numEvents++;
                events.transferBondedEvents.push(TransferBondedEvent(
                    block.chainid,
                    block.timestamp,
                    log.topics[1],
                    log.topics[2],
                    address(uint160(uint256(log.topics[3]))),
                    amount,
                    minAmountOut,
                    totalSent
                ));
            }
        }

        return (startIndex, numEvents);
    }

    function printEvent(TransferSentEvent storage transferSentEvent) internal view {
        console.log("");
        console.log("TransferSent - %x", uint256(transferSentEvent.checkpointId));
        console.log("chainId %s", transferSentEvent.chainId);
        console.log("pathId %x", uint256(transferSentEvent.pathId));
        console.log("checkpointId %x", uint256(transferSentEvent.checkpointId));
        console.log("to %s", transferSentEvent.to);
        console.log("amount %s", transferSentEvent.amount);
        console.log("minAmountOut %s", transferSentEvent.minAmountOut);
        console.log("totalSent %s", transferSentEvent.totalSent);
        console.log("nonce %s", transferSentEvent.nonce);
        console.log("attestedCheckpoint %s", uint256(transferSentEvent.attestedCheckpoint));

        console.log("");
    }

    function printEvent(TransferBondedEvent storage transferBondedEvent) internal view {
        console.log("");
        console.log("TransferBonded - %x", uint256(transferBondedEvent.claimId));
        console.log("chainId %s", transferBondedEvent.chainId);
        console.log("pathId %x", uint256(transferBondedEvent.pathId));
        console.log("to %s", transferBondedEvent.to);
        console.log("amount %s", transferBondedEvent.amount);
        console.log("minAmountOut %s", transferBondedEvent.minAmountOut);
        console.log("totalSent %s", transferBondedEvent.totalSent);
        console.log("");
    }
}
