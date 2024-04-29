// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {Vm} from 'forge-std/Vm.sol';
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Dispatcher, Route} from "../../../contracts/messenger/messenger/Dispatcher.sol";
import {ExecutorManager} from "../../../contracts/messenger/messenger/ExecutorManager.sol";
import {MockExecutor} from "../MockExecutor.sol";

import {
    HUB_CHAIN_ID,
    SPOKE_CHAIN_ID_0,
    SPOKE_CHAIN_ID_1,
    MESSAGE_FEE,
    MAX_BUNDLE_MESSAGES
} from "../libraries/Constants.sol";
import {
    MessengerEventParser,
    MessageSentEvent,
    MessengerEvents
} from "../libraries/MessengerEventParser.sol";
import {ExternalContracts, OPStackConfig} from "../libraries/ExternalContracts.sol";
import {CrossChainTest, Chain} from "../libraries/CrossChainTest.sol";
import {TransporterFixture} from "./TransporterFixture.sol";
import {ITransportLayer} from "../../../contracts/messenger/interfaces/ITransportLayer.sol";

import {console} from "forge-std/console.sol";

contract MessengerFixture is TransporterFixture {
    MessengerEvents messengerEvents;

    mapping(uint256 => Dispatcher) public dispatcherForChainId;
    mapping(uint256 => MockExecutor) public executorForChainId;

    function deployMessengers(uint256[] memory _chainIds) public crossChainBroadcast {
        deployTransporters(_chainIds);

        for (uint256 i = 0; i < _chainIds.length; i++) {
            uint256 _chainId = _chainIds[i];
            on(_chainId);

            ITransportLayer transporter = transporters[_chainId];

            Dispatcher dispatcher = new Dispatcher(address(transporter));

            dispatcher.setRoute(HUB_CHAIN_ID, MESSAGE_FEE, MAX_BUNDLE_MESSAGES);
            dispatcher.setRoute(SPOKE_CHAIN_ID_0, MESSAGE_FEE, MAX_BUNDLE_MESSAGES);
            dispatcher.setRoute(SPOKE_CHAIN_ID_1, MESSAGE_FEE, MAX_BUNDLE_MESSAGES);
            dispatcherForChainId[_chainId] = dispatcher;

            executorForChainId[_chainId] = new MockExecutor();
        }
    }

    function relayMessage(MessageSentEvent storage messageSentEvent) internal crossChainBroadcast {
        uint256 toChainId = messageSentEvent.toChainId;

        on(messageSentEvent.toChainId);

        MockExecutor exector = executorForChainId[toChainId];
        exector.execute(
            messageSentEvent.messageId,
            messageSentEvent.fromChainId,
            messageSentEvent.from,
            messageSentEvent.to,
            messageSentEvent.data
        );
    }

    // function relayMessagesFromLogs(Vm.Log[] memory logs) internal crossChainBroadcast {
    //     MessageSentEvent[] memory messageSentEvents = logs.getMessageSentEvents();
    //     console.log("Found %s events", messageSentEvents.length);

    //     for (uint256 i = 0; i < messageSentEvents.length; i++) {
    //         MessageSentEvent memory messageSentEvent = messageSentEvents[i];
    //         uint256 toChainId = messageSentEvent.toChainId;

    //         on(messageSentEvent.toChainId);

    //         MockExecutor exector = executorForChainId[toChainId];
    //         exector.execute(
    //             messageSentEvent.messageId,
    //             messageSentEvent.fromChainId,
    //             messageSentEvent.from,
    //             messageSentEvent.to,
    //             messageSentEvent.data
    //         );
    //     }
    // }
}
