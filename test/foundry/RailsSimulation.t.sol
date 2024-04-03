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
import {
    HUB_CHAIN_ID,
    SPOKE_CHAIN_ID_0,
    SPOKE_CHAIN_ID_1,
    ONE_TKN
} from "./libraries/Constants.sol";

import {console} from "forge-std/console.sol";

struct SimTransfer {
    uint256 fromChainId;
    uint256 toChainId;
    uint256 amount;
}

contract RailsSimulation_Test is MessengerFixture {
    using MessengerEventParser for Vm.Log[];
    using RailsHubEventParser for Vm.Log[];
    using RailsHubEventParser for TransferSentEvent;
    using RailsHubEventParser for TransferBondedEvent;
    using RailsHubEventParser for RailsHubEvents;

    uint256[] public chainIds;
    mapping(uint256 => IERC20) public tokenForChainId;
    mapping(uint256 => RailsHub) public hubForChainId;

    uint256 public constant AMOUNT = 100 * 1e18;
    uint256 public constant MIN_AMOUNT_OUT = 99 * 1e18;
    uint256 public constant FROM_CHAIN_ID = 11155111;
    uint256 public constant TO_CHAIN_ID = 11155420;

    mapping(address => string) public nameForAddress;

    address public constant deployer = address(1);
    address public constant user1 = address(2);
    address public constant bonder1 = address(3);

    RailsHubEvents hubEvents;

    SimTransfer[] public simTransfers;

    mapping(uint256 => uint256) totalSent;
    mapping(uint256 => uint256) totalBonded;
    mapping(uint256 => uint256) totalFees;
    mapping(uint256 => uint256) totalWithdrawn;
    uint256 totalRate;

    constructor() {
        nameForAddress[deployer] = "DEPLOYER";
        nameForAddress[user1] = "USER 1  ";
        nameForAddress[bonder1] = "BONDER 1";
    }

    function printEthBalance(uint256 chainId, address account) internal broadcastOn(chainId) {
        string memory name = nameForAddress[account];
        IERC20 token = tokenForChainId[chainId];
        uint256 ethBlance = account.balance;
        uint256 tokenBalance = token.balanceOf(account);

        console.log("%s - chainId %s - %s", name, chainId, account);
        console.log("WEI  %s", ethBlance);
    }

    function printTokenBalances() internal {
        console.log("Name     |         From Chain          |         To Chain");
        printTokenBalance(user1);
        printTokenBalance(bonder1);
    }

    function printTokenBalance(address account) internal crossChainBroadcast {
        string memory name = nameForAddress[account];

        on(FROM_CHAIN_ID);
        IERC20 fromToken = tokenForChainId[FROM_CHAIN_ID];
        uint256 fromBalance = fromToken.balanceOf(account);

        on(TO_CHAIN_ID);
        IERC20 toToken = tokenForChainId[TO_CHAIN_ID];
        uint256 toBalance = toToken.balanceOf(account);

        console.log("%s | %s | %s", name, fromBalance, toBalance);
    }

    function printHubTokenBalances() internal crossChainBroadcast {
        on(FROM_CHAIN_ID);
        IERC20 fromToken = tokenForChainId[FROM_CHAIN_ID];
        RailsHub fromHub = hubForChainId[FROM_CHAIN_ID];
        uint256 fromBalance = fromToken.balanceOf(address(fromHub));

        on(TO_CHAIN_ID);
        IERC20 toToken = tokenForChainId[TO_CHAIN_ID];
        RailsHub toHub = hubForChainId[TO_CHAIN_ID];
        uint256 toBalance = toToken.balanceOf(address(toHub));

        console.log("HopHub   |     %s |     %s", fromBalance, toBalance);
    }

    function setUp() public crossChainBroadcast {
        vm.deal(deployer, 10 * 1e18);
        vm.deal(user1, 10 * 1e18);
        vm.deal(bonder1, 10 * 1e18);

        chainIds.push(HUB_CHAIN_ID);
        chainIds.push(SPOKE_CHAIN_ID_0);

        vm.startPrank(deployer);

        deployMessengers(chainIds);

        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            on(chainId);

            IERC20 token = new MockToken();
            token.transfer(address(user1), 1e9 * 1e18);
            token.transfer(address(bonder1), 1e9 * 1e18);
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
                    5_000_000 * ONE_TKN,
                    5_000_000 * ONE_TKN,
                    200000000000000
                );
            }
        }

        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e20));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e20));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e20));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e20));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e20));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e20));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));

        vm.stopPrank();
    }

    function test_runSimulation() public crossChainBroadcast {
        console.log("Running Simulation");
        console.log("");

        for (uint256 i = 0; i < simTransfers.length; i++) {
            processSimTransfer(simTransfers[i]);
        }

        // printTokenBalance(FROM_CHAIN_ID, user1);
        // printTokenBalance(FROM_CHAIN_ID, bonder1);
        // printTokenBalance(TO_CHAIN_ID, user1);
        // printTokenBalance(TO_CHAIN_ID, bonder1);

        printTokenBalances();
        printHubTokenBalances();

        // printTokenBalance(FROM_CHAIN_ID, address(hubForChainId[FROM_CHAIN_ID]));
        // printTokenBalance(TO_CHAIN_ID, address(hubForChainId[TO_CHAIN_ID]));
    }

    function processSimTransfer(SimTransfer storage simTransfer) internal crossChainBroadcast() {
        IERC20 fromToken = tokenForChainId[simTransfer.fromChainId];
        IERC20 toToken = tokenForChainId[simTransfer.toChainId];
        uint256 minAmountOut = 0;

        TransferSentEvent storage transferSentEvent = send(
            user1,
            simTransfer.fromChainId,
            fromToken,
            simTransfer.toChainId,
            toToken,
            user1,
            simTransfer.amount,
            minAmountOut
        );

        on(simTransfer.toChainId);
        uint256 beforeBalance = toToken.balanceOf(user1);
        TransferBondedEvent storage transferBondedEvent = bond(bonder1, transferSentEvent);
        uint256 afterBalance = toToken.balanceOf(user1);

        uint256 sent = transferSentEvent.amount;
        uint256 received = afterBalance - beforeBalance;

        uint256 rate = received * ONE_TKN / transferSentEvent.amount;

        transferSentEvent.printEvent();
        transferBondedEvent.printEvent();
        console.log("rate: %s", rate);
        console.log("");
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

            vm.stopPrank();
        }

        TransferSentEvent storage transferSentEvent;
        {
            Vm.Log[] memory logs = vm.getRecordedLogs();
            (uint256 startIndex, uint256 numEvents) = hubEvents.getTransferSentEvents(logs);
            require (numEvents == 1, "No TransferSentEvent found");
            transferSentEvent = hubEvents.transferSentEvents[startIndex];
        }

        totalSent[fromChainId] += amount;
        totalFees[fromChainId] += transferSentEvent.attestationFee;
        
        return transferSentEvent;
    }

    function bond(address bonder, TransferSentEvent storage transferSentEvent) internal crossChainBroadcast returns (TransferBondedEvent storage) {
        bytes32 pathId = transferSentEvent.pathId;
        RailsHub toRailsHub;
        uint256 toChainId;
        {
            vm.startPrank(bonder);
            uint256 fromChainId = transferSentEvent.chainId;
            on(fromChainId);
            RailsHub fromRailsHub = hubForChainId[fromChainId];

            ( , , uint256 _toChainId, IERC20 toToken) = fromRailsHub.getPathInfo(pathId);
            toChainId = _toChainId;

            on(toChainId);
            toRailsHub = hubForChainId[toChainId];

            uint256 amount = transferSentEvent.amount;
            toToken.approve(address(toRailsHub), amount * 2);
        }
        vm.recordLogs();
        toRailsHub.bond(
            pathId,
            transferSentEvent.checkpoint,
            transferSentEvent.to,
            transferSentEvent.amount,
            transferSentEvent.totalSent,
            transferSentEvent.nonce,
            transferSentEvent.attestedCheckpoint
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        (uint256 startIndex, uint256 numEvents) = hubEvents.getTransferBondedEvents(logs);
        require (numEvents == 1, "No TransferBondedEvent found");
        TransferBondedEvent storage transferBondedEvent = hubEvents.transferBondedEvents[startIndex];

        vm.stopPrank();

        totalBonded[toChainId] += transferBondedEvent.amount;

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
