// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import {Vm} from "forge-std/Vm.sol";
import {CrossChainTest} from "./libraries/CrossChainTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from "../../contracts/test/MockToken.sol";
import {RailsHub} from "../../contracts/rails/RailsHub.sol";
import {ICrossChainFees} from "../../contracts/messenger/interfaces/ICrossChainFees.sol";
import {IMessageDispatcher} from "../../contracts/ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../../contracts/ERC5164/IMessageExecutor.sol";
import {TransporterFixture} from "./fixtures/TransporterFixture.sol";
import {MessengerFixture} from "./fixtures/MessengerFixture.sol";
import {MockExecutor} from "./MockExecutor.sol";
import {MessengerEventParser, SendMessageEvent} from "./libraries/MessengerEventParser.sol";
import {
    RailsHubEventParser,
    RailsHubEvents,
    TransferSentEvent,
    TransferBondedEvent
} from "./libraries/RailsHubEventParser.sol";
import {HUB_CHAIN_ID, SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1} from "./libraries/Constants.sol";

import {console} from "forge-std/console.sol";

contract RailsHub_Test is MessengerFixture {
    using MessengerEventParser for Vm.Log[];
    using RailsHubEventParser for Vm.Log[];
    using RailsHubEventParser for TransferSentEvent;
    using RailsHubEventParser for TransferBondedEvent;
    using RailsHubEventParser for RailsHubEvents;

    uint256[] public chainIds;
    mapping(uint256 => IERC20) public tokenForChainId;
    mapping(uint256 => RailsHub) public hubForChainId;

    uint256 public constant AMOUNT = 100 * 10e18;
    uint256 public constant MIN_AMOUNT_OUT = 99 * 10e18;
    uint256 public constant FROM_CHAIN_ID = 11155111;
    uint256 public constant TO_CHAIN_ID = 11155420;

    mapping(address => string) public nameForAddress;

    address public constant deployer = address(1);
    address public constant user1 = address(2);
    address public constant user2 = address(3);
    address public constant bonder1 = address(4);

    RailsHubEvents hubEvents;

    constructor() {
        nameForAddress[deployer] = "deployer";
        nameForAddress[user1] = "user1";
        nameForAddress[user2] = "user2";
        nameForAddress[bonder1] = "bonder1";
    }

    function printBalance(address account) internal {
        printBalance(block.chainid, account);
    }

    function printBalance(uint256 chainId, address account) internal broadcastOn(chainId) {
        string memory name = nameForAddress[account];
        IERC20 token = tokenForChainId[chainId];
        uint256 ethBlance = account.balance;
        uint256 tokenBalance = token.balanceOf(account);

        console.log("%s - chainId %s - %s", name, chainId, account);
        console.log("WEI  %s", ethBlance);
        console.log("%s %s", "MOCK", tokenBalance);
    }

    function setUp() public crossChainBroadcast {
        vm.deal(deployer, 10e18);
        vm.deal(user1, 10e18);
        vm.deal(user2, 10e18);
        vm.deal(bonder1, 10e18);

        chainIds.push(HUB_CHAIN_ID);
        chainIds.push(SPOKE_CHAIN_ID_0);
        // chainIds.push(SPOKE_CHAIN_ID_1);

        vm.startPrank(deployer);

        deployMessengers(chainIds);

        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            on(chainId);

            IERC20 token = new MockToken();
            token.transfer(address(user1), 1000 * 10e18);
            token.transfer(address(user2), 1000 * 10e18);
            token.transfer(address(bonder1), 1000 * 10e18);
            tokenForChainId[chainId] = token;
        }

        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            on(chainId);
            RailsHub hub = new RailsHub();
            hubForChainId[chainId] = hub;
            IERC20 token = tokenForChainId[chainId];

            for (uint256 j = 0; j < chainIds.length; j++) {
                uint256 counterpartChainId = chainIds[j];
                if (counterpartChainId == chainId) continue;
                IERC20 counterpartToken = tokenForChainId[counterpartChainId];
                bytes32 pathId = hub.initPath(
                    token,
                    counterpartChainId,
                    counterpartToken,
                    IMessageDispatcher(address(dispatcherForChainId[chainId])),
                    IMessageExecutor(address(executorForChainId[chainId])),
                    0
                );
            }
        }
        vm.stopPrank();
    }

    function test_happyPathRails() public crossChainBroadcast {
        uint256 fromChainId = FROM_CHAIN_ID;
        IERC20 fromToken = tokenForChainId[FROM_CHAIN_ID];
        uint256 toChainId = TO_CHAIN_ID;
        IERC20 toToken = tokenForChainId[TO_CHAIN_ID];
        uint256 amount = AMOUNT;
        uint256 minAmountOut = MIN_AMOUNT_OUT;

        RailsHub fromRailsHub = hubForChainId[FROM_CHAIN_ID];
        RailsHub toRailsHub = hubForChainId[TO_CHAIN_ID];
        nameForAddress[address(fromRailsHub)] = "fromRailsHub";
        nameForAddress[address(toRailsHub)] = "toRailsHub";

        console.log("");
        console.log("====================================");
        console.log("          INITIAL BALANCES");
        console.log("====================================");
        console.log("");

        on(fromChainId);
        printBalance(user1);
        printBalance(bonder1);
        printBalance(address(fromRailsHub));
        on(toChainId);
        printBalance(user1);
        printBalance(bonder1);
        printBalance(address(toRailsHub));

        console.log("");
        console.log("====================================");
        console.log("               SEND");
        console.log("====================================");
        console.log("");

        // send transfer
        TransferSentEvent storage transferSentEvent = send(
            user1,
            fromChainId,
            fromToken,
            toChainId,
            toToken,
            user1,
            amount,
            minAmountOut
        );

        // printBalance(fromChainId, user1);
        printBalance(fromChainId, address(fromRailsHub));

        console.log("");
        console.log("====================================");
        console.log("               BOND");
        console.log("====================================");
        console.log("");

        // bond transfer
        TransferBondedEvent storage transferBondedEvent = bond(bonder1, transferSentEvent);

        printBalance(toChainId, user1);
        printBalance(toChainId, bonder1);

        console.log("");
        console.log("====================================");
        console.log("             SEND BACK");
        console.log("====================================");
        console.log("");

        // send reverse direction
        send(
            user2,
            toChainId,
            toToken,
            fromChainId,
            fromToken,
            user2,
            amount,
            minAmountOut
        );

        printBalance(toChainId, address(toRailsHub));

        // ToDo: advance time

        console.log("");
        console.log("====================================");
        console.log("             WITHDRAW");
        console.log("====================================");
        console.log("");

        withdraw(
            toChainId,
            bonder1,
            amount,
            transferBondedEvent.pathId,
            transferBondedEvent.timestamp
        );

        printBalance(toChainId, bonder1);
        printBalance(toChainId, address(toRailsHub));
    }

    function send(
        address from,
        uint256 fromChainId,
        IERC20 fromToken,
        uint256 toChainId,
        IERC20 toToken,
        address to,
        uint256 amount,
        uint256 minAmountOut
    )
        internal
        broadcastOn(fromChainId)
        returns (TransferSentEvent storage)
    {
        vm.startPrank(from);
        RailsHub fromRailsHub = hubForChainId[fromChainId];
        bytes32 pathId = fromRailsHub.getPathId(fromChainId, IERC20(address(fromToken)), toChainId, IERC20(address(toToken)));
        uint256 fee = fromRailsHub.getFee(pathId);

        fromToken.approve(address(fromRailsHub), amount);
        vm.recordLogs();
        bytes32 attestedCheckpoint = bytes32(0);
        fromRailsHub.send{
            value: fee
        }(
            pathId,
            to,
            amount,
            minAmountOut,
            attestedCheckpoint
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 startIndex, uint256 numEvents) = hubEvents.getTransferSentEvents(logs);
        require (numEvents == 1, "No TransferSentEvent found");
        TransferSentEvent storage transferSentEvent = hubEvents.transferSentEvents[startIndex];
        transferSentEvent.printEvent();
        vm.stopPrank();

        return transferSentEvent;
    }

    function bond(address bonder, TransferSentEvent storage transferSentEvent) internal crossChainBroadcast returns (TransferBondedEvent storage) {
        bytes32 pathId = transferSentEvent.pathId;
        RailsHub toRailsHub;
        {
            vm.startPrank(bonder);
            uint256 fromChainId = transferSentEvent.chainId;
            on(fromChainId);
            RailsHub fromRailsHub = hubForChainId[fromChainId];

            ( , , uint256 toChainId, IERC20 toToken) = fromRailsHub.getPathInfo(pathId);

            on(toChainId);
            toRailsHub = hubForChainId[toChainId];

            uint256 amount = transferSentEvent.amount;
            toToken.approve(address(toRailsHub), amount);
        }
        vm.recordLogs();
        toRailsHub.bond(
            pathId,
            transferSentEvent.checkpoint,
            transferSentEvent.to,
            transferSentEvent.amount,
            transferSentEvent.minAmountOut,
            transferSentEvent.totalSent,
            transferSentEvent.nonce,
            transferSentEvent.attestedCheckpoint
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 startIndex, uint256 numEvents) = hubEvents.getTransferBondedEvents(logs);
        require (numEvents == 1, "No TransferBondedEvent found");
        TransferBondedEvent storage transferBondedEvent = hubEvents.transferBondedEvents[startIndex];

        transferBondedEvent.printEvent();
        vm.stopPrank();

        return transferBondedEvent;
    }

    function withdraw(
        uint256 chainId,
        address bonder,
        uint256 amount,
        bytes32 pathId,
        uint256 time
    )
        internal
        broadcastOn(chainId)
    {
        vm.startPrank(bonder);
        RailsHub hub = hubForChainId[chainId];

        hub.withdrawAll(pathId, time);
        vm.stopPrank();
    }
}
