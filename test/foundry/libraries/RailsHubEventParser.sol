// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/Console.sol";

struct TransferSentEvent{
    uint256 chainId;
    uint256 timestamp;
    bytes32 pathId;
    bytes32 transferId;
    bytes32 checkpoint;
    address to;
    uint256 amount;
    uint256 attestationFee;
    uint256 totalSent;
    uint256 nonce;
    bytes32 attestedCheckpoint;
}

struct TransferBondedEvent{
    uint256 chainId;
    uint256 timestamp;
    bytes32 pathId;
    bytes32 transferId;
    bytes32 checkpoint;
    address to;
    uint256 amount;
    uint256 totalSent;
}

struct RailsHubEvents {
    TransferSentEvent[] transferSentEvents;
    TransferBondedEvent[] transferBondedEvents;
}

/// @notice - WARNING: Do not switch chains before parsing logs. block.chainid is assigned to the event struct.
library RailsHubEventParser {
    function getTransferSentEvents(
        RailsHubEvents storage events,
        Vm.Log[] memory logs
    )
        internal
        returns(uint256 startIndex, uint256 numEvents)
    {
        bytes32 eventSignature = keccak256(abi.encodePacked("TransferSent(bytes32,bytes32,bytes32,address,uint256,uint256,uint256,uint256,bytes32)"));

        startIndex = events.transferSentEvents.length;
        numEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {

            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                (
                    bytes32 transferId,
                    uint256 amount,
                    uint256 attestationFee,
                    uint256 totalSent,
                    uint256 nonce,
                    bytes32 attestedCheckpoint
                ) = abi.decode(log.data, (bytes32,uint256,uint256,uint256,uint256,bytes32));

                numEvents++;
                events.transferSentEvents.push(TransferSentEvent(
                    block.chainid,
                    block.timestamp,
                    log.topics[1],
                    transferId,
                    log.topics[2],
                    address(uint160(uint256(log.topics[3]))),
                    amount,
                    attestationFee,
                    totalSent,
                    nonce,
                    attestedCheckpoint
                ));
            }
        }
    }

    function getTransferBondedEvents(
        RailsHubEvents storage events,
        Vm.Log[] memory logs
    )
        internal
        returns(uint256 startIndex, uint256 numEvents)
    {
        bytes32 eventSignature = keccak256(abi.encodePacked("TransferBonded(bytes32,bytes32,bytes32,address,uint256,uint256)"));

        startIndex = events.transferBondedEvents.length;
        numEvents = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                (
                    bytes32 transferId,
                    uint256 amountOut,
                    uint256 totalSent
                ) = abi.decode(log.data, (bytes32, uint256, uint256));

                numEvents++;
                events.transferBondedEvents.push(TransferBondedEvent(
                    block.chainid,
                    block.timestamp,
                    log.topics[1],
                    transferId,
                    log.topics[2],
                    address(uint160(uint256(log.topics[3]))),
                    amountOut,
                    totalSent
                ));
            }
        }

        return (startIndex, numEvents);
    }

    function printEvent(TransferSentEvent storage transferSentEvent) internal view {
        console.log("%s sent from chain %s - %x", transferSentEvent.amount, transferSentEvent.chainId, uint256(transferSentEvent.checkpoint));
    }

    function printEvent(TransferBondedEvent storage transferBondedEvent) internal view {
        console.log("%s received on chain %s - %x", transferBondedEvent.amount, transferBondedEvent.chainId, uint256(transferBondedEvent.checkpoint));
    }

    function printEventDetails(TransferSentEvent storage transferSentEvent) internal view {
        console.log("");
        console.log("TransferSent - %x", uint256(transferSentEvent.checkpoint));
        console.log("chainId %s", transferSentEvent.chainId);
        console.log("pathId %x", uint256(transferSentEvent.pathId));
        console.log("checkpoint %x", uint256(transferSentEvent.checkpoint));
        console.log("to %s", transferSentEvent.to);
        console.log("amount %s", transferSentEvent.amount);
        console.log("totalSent %s", transferSentEvent.totalSent);
        console.log("nonce %s", transferSentEvent.nonce);
        console.log("attestedCheckpoint %s", uint256(transferSentEvent.attestedCheckpoint));

        console.log("");
    }

    function printEventDetails(TransferBondedEvent storage transferBondedEvent) internal view {
        console.log("");
        console.log("TransferBonded - %x", uint256(transferBondedEvent.transferId));
        console.log("chainId %s", transferBondedEvent.chainId);
        console.log("pathId %x", uint256(transferBondedEvent.pathId));
        console.log("to %s", transferBondedEvent.to);
        console.log("amountOut %s", transferBondedEvent.amount);
        console.log("totalSent %s", transferBondedEvent.totalSent);
        console.log("");
    }
}
