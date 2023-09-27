// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/Console.sol";

struct TransferSentEvent{
    uint256 fromChainId;
    bytes32 claimId;
    bytes32 tokenBusId;
    address to;
    uint256 amount;
    uint256 minAmountOut;
    uint256 minClaimsSent;
}

struct TransferBondedEvent{
    uint256 toChainId;
    bytes32 claimId;
    bytes32 tokenBusId;
    address to;
    uint256 amount;
    uint256 minAmountOut;
    uint256 minClaimsSent;
}

/// @notice - WARNING: Do not switch chains before parsing logs. block.chainid is assigned to the event struct.
library LiquidityHubEventParser {
    function getTransferSentEvents(Vm.Log[] memory logs) internal view returns(TransferSentEvent[] memory) {
        bytes32 eventSignature = keccak256(abi.encodePacked("TransferSent(bytes32,bytes32,address,uint256,uint256,uint256)"));

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
                transferSentEvents[j].fromChainId = block.chainid;
                transferSentEvents[j].claimId = log.topics[1];
                transferSentEvents[j].tokenBusId = log.topics[2];
                transferSentEvents[j].to = address(uint160(uint256(log.topics[3])));
                (
                    transferSentEvents[j].amount,
                    transferSentEvents[j].minAmountOut,
                    transferSentEvents[j].minClaimsSent
                ) = abi.decode(log.data, (uint256, uint256, uint256));
                j++;
            }
        }

        return transferSentEvents;
    }

    function getTransferBondedEvents(Vm.Log[] memory logs) internal view returns(TransferBondedEvent[] memory) {
        bytes32 eventSignature = keccak256(abi.encodePacked("TransferBonded(bytes32,bytes32,address,uint256,uint256,uint256)"));

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
                transferBondedEvents[j].toChainId = block.chainid;
                transferBondedEvents[j].claimId = log.topics[1];
                transferBondedEvents[j].tokenBusId = log.topics[2];
                transferBondedEvents[j].to = address(uint160(uint256(log.topics[3])));
                (
                    transferBondedEvents[j].amount,
                    transferBondedEvents[j].minAmountOut,
                    transferBondedEvents[j].minClaimsSent
                ) = abi.decode(log.data, (uint256, uint256, uint256));
                j++;
            }
        }

        return transferBondedEvents;
    }
}
