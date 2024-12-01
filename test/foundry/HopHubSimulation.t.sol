// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import {Vm} from "forge-std/Vm.sol";
import {CrossChainTest} from "./libraries/CrossChainTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../../contracts/test/MockToken.sol";
import {RailsGateway} from "../../contracts/rails/RailsGateway.sol";
import {ICrossChainFees} from "../../contracts/messenger/interfaces/ICrossChainFees.sol";
import {IMessageDispatcher} from "../../contracts/ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../../contracts/ERC5164/IMessageExecutor.sol";
import {TransporterFixture} from "./fixtures/TransporterFixture.sol";
import {RailsFixture} from "./fixtures/RailsFixture.sol";
import {MockExecutor} from "./MockExecutor.sol";
import {
    MessengerEventParser,
    MessageSentEvent,
    MessengerEvents
} from "./libraries/MessengerEventParser.sol";
import {
    RailsGatewayEventParser,
    RailsGatewayEvents,
    TransferSentEvent,
    TransferBondedEvent
} from "./libraries/RailsGatewayEventParser.sol";
import {
    L1_CHAIN_ID,
    HUB_CHAIN_ID,
    SPOKE_CHAIN_ID_0,
    SPOKE_CHAIN_ID_1,
    ONE_TKN
} from "./libraries/Constants.sol";
import {StringLib} from "./libraries/StringLib.sol";
import {console} from "forge-std/console.sol";
import {SimTransferLib, SimTransfer} from "./libraries/SimTransferLib.sol";

contract HopHubSimulation_Test is RailsFixture {
    using MessengerEventParser for MessengerEvents;
    using RailsGatewayEventParser for Vm.Log[];
    using RailsGatewayEventParser for TransferSentEvent;
    using RailsGatewayEventParser for TransferBondedEvent;
    using RailsGatewayEventParser for RailsGatewayEvents;
    using StringLib for string;
    using StringLib for uint256;
    using StringLib for string[];

    function setUp() public crossChainBroadcast {
        setUpRails();
    }

    function test_runHopHubSimulation() public crossChainBroadcast {
        console.log("Running Simulation");
        console.log("");

        SimTransfer[] memory simTransfers = SimTransferLib.getSimTransfers(5);
        for (uint256 i = 0; i < simTransfers.length; i++) {
            processSimTransfer(simTransfers[i]);
        }
    
        console.log("");
        printTokenBalances();
        printGatewayTokenBalances();

        console.log("");
        console.log("Bonder withdrawing...");
        console.log("");

        withdrawAll();

        printTokenBalances();
        printGatewayTokenBalances();


        console.log("");
        console.log("Relaying final messages for hard confirmation...");
        console.log("");

        relayMessage(latestMessageSent[SPOKE_CHAIN_ID_0]);
        relayMessage(latestMessageSent[SPOKE_CHAIN_ID_1]);

        console.log("");
        console.log("Bonder withdrawing...");
        console.log("");

        withdrawAll();

        printTokenBalances();
        printGatewayTokenBalances();

        uint256 _totalSent = totalSent[SPOKE_CHAIN_ID_0] + totalSent[SPOKE_CHAIN_ID_1];
        uint256 _totalBonded = totalBonded[SPOKE_CHAIN_ID_0] + totalBonded[SPOKE_CHAIN_ID_1];
        uint256 _totalWithdrawn = totalWithdrawn[SPOKE_CHAIN_ID_0] + totalWithdrawn[SPOKE_CHAIN_ID_1];
        uint256 _avgRate = 0;
        if (simTransfers.length > 0) {
            _avgRate = (totalRate[SPOKE_CHAIN_ID_0] + totalRate[SPOKE_CHAIN_ID_1]) / simTransfers.length;
        }

        console.log("");
        console.log(StringLib.toRow("totalSent", _totalSent.formatDollar(18, 18)));
        console.log(StringLib.toRow("totalBonded", _totalBonded.formatDollar(18, 18)));
        console.log(StringLib.toRow("totalWithdrawn", _totalWithdrawn.formatDollar(18, 18)));
        console.log("");
    }

    function withdrawAll() internal crossChainBroadcast {
        IERC20 hubToken = tokenForChainId[hubChainId];
        RailsGateway hubGateway = gatewayForChainId[hubChainId];
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 spokeChainId = chainIds[i];
            if (spokeChainId == hubChainId) continue;
            if (spokeChainId == l1ChainId) continue;

            IERC20 spokeToken = tokenForChainId[spokeChainId];
            RailsGateway spokeGateway = gatewayForChainId[spokeChainId];
            on(spokeChainId);
            bytes32 pathId = spokeGateway.getPathId(hubChainId, hubToken, spokeChainId, spokeToken);

            console.log("pathId %s %s %x", hubChainId, spokeChainId, uint256(pathId));
            console.log("withdraw hub", hubChainId);
            withdrawAll(hubChainId, pathId, bonder1);
            console.log("withdraw spoke", spokeChainId);
            withdrawAll(spokeChainId, pathId, bonder1);
        }
    }

    function processSimTransfer(SimTransfer memory simTransfer) internal crossChainBroadcast {
        IERC20 fromToken = tokenForChainId[simTransfer.fromChainId];
        IERC20 hubToken = tokenForChainId[hubChainId];
        IERC20 toToken = tokenForChainId[simTransfer.toChainId];

        (
            TransferSentEvent storage transferSentEvent0,
            MessageSentEvent storage messageSentEvent
        ) = send(
            user1,
            simTransfer.fromChainId,
            fromToken,
            hubChainId,
            hubToken,
            simTransfer.toChainId,
            toToken,
            user1,
            simTransfer.amount
        );
        transferSentEvent0.printEvent();

        on(simTransfer.toChainId);
        uint256 beforeBalance = toToken.balanceOf(user1);
        {
            (
                TransferBondedEvent storage transferBondedEvent0,
                TransferSentEvent storage transferSentEvent1
            ) = bond(bonder1, transferSentEvent0);
            transferBondedEvent0.printEvent();

            (
                TransferBondedEvent storage transferBondedEvent1,
            ) = bond(bonder1, transferSentEvent1);
            transferBondedEvent1.printEvent();
        }

        {
            uint256 afterBalance = toToken.balanceOf(user1);
            uint256 received = afterBalance - beforeBalance;
            uint256 rate = received * ONE_TKN / simTransfer.amount;
            console.log("rate", rate);
            totalRate[simTransfer.fromChainId] += rate;
        }

        latestMessageSent[simTransfer.fromChainId] = messageSentEvent;
    }
}
