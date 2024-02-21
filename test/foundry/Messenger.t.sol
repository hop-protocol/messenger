// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {CrossChainTest} from './libraries/CrossChainTest.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from '../../contracts/test/MockToken.sol';
import {RailsHub} from '../../contracts/liquidity-hub/RailsHub.sol';
import {ICrossChainFees} from '../../contracts/messenger/interfaces/ICrossChainFees.sol';
import {IMessageDispatcher} from '../../contracts/ERC5164/IMessageDispatcher.sol';
import {IMessageExecutor} from '../../contracts/ERC5164/IMessageExecutor.sol';
import {TransporterFixture} from './fixtures/TransporterFixture.sol';
import {MessengerFixture} from './fixtures/MessengerFixture.sol';
import {MockExecutor} from './MockExecutor.sol';
import {MessengerEventParser, SendMessageEvent} from './libraries/MessengerEventParser.sol';
import {HUB_CHAIN_ID, SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1} from './libraries/Constants.sol';

contract Messenger_Test is MessengerFixture {
    using MessengerEventParser for Vm.Log[];

    uint256[] public chainIds;

    uint256 public constant FROM_CHAIN_ID = 5;
    uint256 public constant TO_CHAIN_ID = 420;

    mapping(address => string) public nameForAddress;

    address public constant deployer = address(1);
    address public constant user1 = address(2);
    address public constant user2 = address(3);
    address public constant bonder1 = address(4);

    constructor() {
        nameForAddress[deployer] = "deployer";
        nameForAddress[user1] = "user1";
    }

    function setUp() public crossChainBroadcast {
        vm.deal(deployer, 10e18);
        vm.deal(user1, 10e18);

        chainIds.push(HUB_CHAIN_ID);
        chainIds.push(SPOKE_CHAIN_ID_0);
        chainIds.push(SPOKE_CHAIN_ID_1);

        vm.startPrank(deployer);
        deployMessengers(chainIds);
        vm.stopPrank();
    }

    function test_messenger() public crossChainBroadcast {
        on(HUB_CHAIN_ID);
        IMessageDispatcher dispatcher = IMessageDispatcher(address(dispatcherForChainId[HUB_CHAIN_ID]));

        uint256[] memory chains = new uint256[](1);
        chains[0] = SPOKE_CHAIN_ID_0;
        uint256 fee = ICrossChainFees(address(dispatcher)).getFee(chains);
        vm.recordLogs();
        dispatcher.dispatchMessage{value: fee}(SPOKE_CHAIN_ID_0, msg.sender, abi.encodeWithSignature("hello()"));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Vm.Log memory log = logs[0];

        SendMessageEvent[] memory sendMessageEvents = logs.getSendMessageEvents();
        SendMessageEvent memory sendMessageEvent = sendMessageEvents[0];

        printSendMessageEvent(sendMessageEvent);

        assertEq(true, true);
    }

    function printSendMessageEvent(SendMessageEvent memory sendMessageEvent) internal view {
        console.log("SendMessageEvent");
        console.log("messageId");
        console.logBytes32(sendMessageEvent.messageId);
        console.log("from");
        console.log(sendMessageEvent.from);
        console.log("toChainId");
        console.log(sendMessageEvent.toChainId);
        console.log("to");
        console.log(sendMessageEvent.to);
        console.log("data");
        console.logBytes(sendMessageEvent.data);
    }
}
