// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import {Vm} from "forge-std/Vm.sol";
import {CrossChainTest} from "./libraries/CrossChainTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../../contracts/test/MockToken.sol";
import {RailsGateway, Hop} from "../../contracts/rails/RailsGateway.sol";
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
    SPOKE_CHAIN_ID_0,
    SPOKE_CHAIN_ID_1,
    ONE_TKN
} from "./libraries/Constants.sol";
import {StringLib} from "./libraries/StringLib.sol";
import {console} from "forge-std/console.sol";
import {SimTransferLib, SimTransfer} from "./libraries/SimTransferLib.sol";

contract RailsSimulation_Test is RailsFixture {
    using MessengerEventParser for MessengerEvents;
    using RailsGatewayEventParser for Vm.Log[];
    using RailsGatewayEventParser for TransferSentEvent;
    using RailsGatewayEventParser for TransferBondedEvent;
    using RailsGatewayEventParser for RailsGatewayEvents;
    using StringLib for string;
    using StringLib for uint256;
    using StringLib for string[];

    uint256 constant FROM_CHAIN_ID = SPOKE_CHAIN_ID_0;
    uint256 constant TO_CHAIN_ID = SPOKE_CHAIN_ID_1;


    function setUp() public crossChainBroadcast {
        setUpRails();
    }

    function test_runSimulation() public crossChainBroadcast {
        console.log("Running Simulation");
        console.log("");

        SimTransfer[] memory simTransfers = simulateTransfers(true);
    
        console.log("");
        printTokenBalances(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1);
        printGatewayTokenBalances(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1);

        console.log("");
        console.log("Bonder withdrawing...");
        console.log("");

        withdrawAll();

        printTokenBalances(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1);
        printGatewayTokenBalances(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1);

        console.log("");
        console.log("Relaying final messages for hard confirmation...");
        console.log("");

        relayMessage(latestMessageSent[FROM_CHAIN_ID]);
        relayMessage(latestMessageSent[TO_CHAIN_ID]);

        console.log("");
        console.log("Bonder withdrawing...");
        console.log("");

        withdrawAll();

        printTokenBalances(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1);
        printGatewayTokenBalances(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1);

        uint256 _totalSent = totalSent[FROM_CHAIN_ID] + totalSent[TO_CHAIN_ID];
        uint256 _totalBonded = totalBonded[FROM_CHAIN_ID] + totalBonded[TO_CHAIN_ID];
        uint256 _totalWithdrawn = totalWithdrawn[FROM_CHAIN_ID] + totalWithdrawn[TO_CHAIN_ID];
        uint256 _avgRate = 0;
        if (simTransfers.length > 0) {
            _avgRate = (totalRate[FROM_CHAIN_ID] + totalRate[TO_CHAIN_ID]) / simTransfers.length;
        }

        console.log("");
        console.log(StringLib.toRow("totalSent", _totalSent.formatDollar(18, 18)));
        console.log(StringLib.toRow("totalBonded", _totalBonded.formatDollar(18, 18)));
        console.log(StringLib.toRow("totalWithdrawn", _totalWithdrawn.formatDollar(18, 18)));
        console.log("");
    }

    function withdrawAll() internal crossChainBroadcast {
        IERC20 fromToken = tokenForChainId[FROM_CHAIN_ID];
        IERC20 toToken = tokenForChainId[TO_CHAIN_ID];
        RailsGateway fromRailsGateway = gatewayForChainId[FROM_CHAIN_ID];
        bytes32 pathId = fromRailsGateway.getPathId(FROM_CHAIN_ID, fromToken, TO_CHAIN_ID, toToken, initialReserve);

        withdraw(FROM_CHAIN_ID, pathId, BONDER1);
        withdraw(TO_CHAIN_ID, pathId, BONDER1);
    }
}
