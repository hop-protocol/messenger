// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/Console.sol";

struct TransferSentEvent{
    uint256 chainId;
    bytes32 claimId;
    bytes32 tokenBusId;
    address to;
    uint256 amount;
    uint256 minAmountOut;
    uint256 sourceClaimsSent;
    uint256 bonus;
}

struct TransferBondedEvent{
    uint256 chainId;
    bytes32 claimId;
    bytes32 tokenBusId;
    address to;
    uint256 amount;
    uint256 minAmountOut;
    uint256 sourceClaimsSent;
    uint256 fee;
}

/// @notice - WARNING: Do not switch chains before parsing logs. block.chainid is assigned to the event struct.
library LiquidityHubEventParser {
    function getTransferSentEvents(Vm.Log[] memory logs) internal view returns(TransferSentEvent[] memory) {
        bytes32 eventSignature = keccak256(abi.encodePacked("TransferSent(bytes32,bytes32,address,uint256,uint256,uint256,uint256)"));

        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                count++;
            }
        }

        TransferSentEvent[] memory transferSentEvents = new TransferSentEvent[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                transferSentEvents[j].chainId = block.chainid;
                transferSentEvents[j].claimId = log.topics[1];
                transferSentEvents[j].tokenBusId = log.topics[2];
                transferSentEvents[j].to = address(uint160(uint256(log.topics[3])));
                (
                    transferSentEvents[j].amount,
                    transferSentEvents[j].minAmountOut,
                    transferSentEvents[j].sourceClaimsSent,
                    transferSentEvents[j].bonus
                ) = abi.decode(log.data, (uint256, uint256, uint256, uint256));
                j++;
            }
        }

        return transferSentEvents;
    }

    function getTransferBondedEvents(Vm.Log[] memory logs) internal view returns(TransferBondedEvent[] memory) {
        bytes32 eventSignature = keccak256(abi.encodePacked("TransferBonded(bytes32,bytes32,address,uint256,uint256,uint256,uint256)"));

        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                count++;
            }
        }

        TransferBondedEvent[] memory transferBondedEvents = new TransferBondedEvent[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory log = logs[i];
            if (log.topics[0] == eventSignature) {
                transferBondedEvents[j].chainId = block.chainid;
                transferBondedEvents[j].claimId = log.topics[1];
                transferBondedEvents[j].tokenBusId = log.topics[2];
                transferBondedEvents[j].to = address(uint160(uint256(log.topics[3])));
                (
                    transferBondedEvents[j].amount,
                    transferBondedEvents[j].minAmountOut,
                    transferBondedEvents[j].sourceClaimsSent,
                    transferBondedEvents[j].fee
                ) = abi.decode(log.data, (uint256, uint256, uint256, uint256));
                j++;
            }
        }

        return transferBondedEvents;
    }

    function printEvent(TransferSentEvent memory transferSentEvent) internal view {
        console.log("");
        console.log("TransferSent - %x", uint256(transferSentEvent.claimId));
        console.log("chainId %s", transferSentEvent.chainId);
        console.log("tokenBusId %x", uint256(transferSentEvent.tokenBusId));
        console.log("to %s", transferSentEvent.to);
        console.log("amount %s", transferSentEvent.amount);
        console.log("minAmountOut %s", transferSentEvent.minAmountOut);
        console.log("sourceClaimsSent %s", transferSentEvent.sourceClaimsSent);
        console.log("bonus %s", transferSentEvent.bonus);
        console.log("");
    }

    function printEvent(TransferBondedEvent memory transferBondedEvent) internal view {
        console.log("");
        console.log("TransferBonded - %x", uint256(transferBondedEvent.claimId));
        console.log("chainId %s", transferBondedEvent.chainId);
        console.log("tokenBusId %x", uint256(transferBondedEvent.tokenBusId));
        console.log("to %s", transferBondedEvent.to);
        console.log("amount %s", transferBondedEvent.amount);
        console.log("minAmountOut %s", transferBondedEvent.minAmountOut);
        console.log("sourceClaimsSent %s", transferBondedEvent.sourceClaimsSent);
        console.log("fee %s", transferBondedEvent.fee);
        console.log("");
    }
}
