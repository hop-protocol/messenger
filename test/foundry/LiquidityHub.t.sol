// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import {Vm} from "forge-std/Vm.sol";
import {CrossChainTest} from './libraries/CrossChainTest.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockToken} from '../../contracts/test/MockToken.sol';
import {LiquidityHub} from '../../contracts/liquidity-hub/LiquidityHub.sol';
import {ICrossChainFees} from '../../contracts/messenger/interfaces/ICrossChainFees.sol';
import {IMessageDispatcher} from '../../contracts/ERC5164/IMessageDispatcher.sol';
import {IMessageExecutor} from '../../contracts/ERC5164/IMessageExecutor.sol';
import {TransporterFixture} from './fixtures/TransporterFixture.sol';
import {MessengerFixture} from './fixtures/MessengerFixture.sol';
import {MockExecutor} from './MockExecutor.sol';
import {MessengerEventParser, SendMessageEvent} from './libraries/MessengerEventParser.sol';
import {
    LiquidityHubEventParser,
    TransferSentEvent,
    TransferBondedEvent
} from './libraries/LiquidityHubEventParser.sol';
import {HUB_CHAIN_ID, SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1} from './libraries/Constants.sol';

import {console} from "forge-std/console.sol";

contract LiquidityHub_Test is MessengerFixture {
    using MessengerEventParser for Vm.Log[];
    using LiquidityHubEventParser for Vm.Log[];

    uint256[] public chainIds;
    mapping(uint256 => IERC20) public tokenForChainId;
    mapping(uint256 => LiquidityHub) public liquidityHubForChainId;

    uint256 public constant AMOUNT = 100 * 10e18;
    uint256 public constant MIN_AMOUNT_OUT = 99 * 10e18;
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
        string[2][] memory rpcs = vm.rpcUrls();
        console.log(rpcs[0][0]);
        console.log(rpcs[0][1]);
        vm.deal(deployer, 10e18);
        vm.deal(user1, 10e18);
        vm.deal(user2, 10e18);
        vm.deal(bonder1, 10e18);

        chainIds.push(HUB_CHAIN_ID);
        chainIds.push(SPOKE_CHAIN_ID_0);
        chainIds.push(SPOKE_CHAIN_ID_1);

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
            LiquidityHub liquidityHub = new LiquidityHub(
                IMessageDispatcher(address(dispatcherForChainId[chainId])),
                IMessageExecutor(address(executorForChainId[chainId]))
            );
            liquidityHubForChainId[chainId] = liquidityHub;
            IERC20 token = tokenForChainId[chainId];

            for (uint256 j = 0; j < chainIds.length; j++) {
                uint256 counterpartChainId = chainIds[j];
                if (counterpartChainId == chainId) continue;
                IERC20 counterpartToken = tokenForChainId[counterpartChainId];
                liquidityHub.initTokenBus(token, counterpartChainId, counterpartToken);
            }
        }
        vm.stopPrank();
    }

    function test_happyPathLiquidityHub() public crossChainBroadcast {
        uint256 fromChainId = FROM_CHAIN_ID;
        IERC20 fromToken = tokenForChainId[FROM_CHAIN_ID];
        uint256 toChainId = TO_CHAIN_ID;
        IERC20 toToken = tokenForChainId[TO_CHAIN_ID];
        uint256 amount = AMOUNT;
        uint256 minAmountOut = MIN_AMOUNT_OUT;

        LiquidityHub fromLiquidityHub = liquidityHubForChainId[FROM_CHAIN_ID];
        LiquidityHub toLiquidityHub = liquidityHubForChainId[TO_CHAIN_ID];
        nameForAddress[address(fromLiquidityHub)] = "fromLiquidityHub";
        nameForAddress[address(toLiquidityHub)] = "toLiquidityHub";

        console.log("");
        console.log("====================================");
        console.log("          INITIAL BALANCES");
        console.log("====================================");
        console.log("");

        on(fromChainId);
        printBalance(user1);
        printBalance(bonder1);
        printBalance(address(fromLiquidityHub));
        on(toChainId);
        printBalance(user1);
        printBalance(bonder1);
        printBalance(address(toLiquidityHub));

        console.log("");
        console.log("====================================");
        console.log("               SEND");
        console.log("====================================");
        console.log("");

        // send transfer
        TransferSentEvent memory transferSentEvent = send(
            user1,
            fromChainId,
            fromToken,
            toChainId,
            toToken,
            user1,
            amount,
            minAmountOut
        );

        printBalance(fromChainId, user1);
        printBalance(fromChainId, address(fromLiquidityHub));

        console.log("");
        console.log("====================================");
        console.log("               BOND");
        console.log("====================================");
        console.log("");

        // bond transfer
        TransferBondedEvent memory transferBondedEvent = bond(bonder1, transferSentEvent);

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

        printBalance(toChainId, address(toLiquidityHub));

        // ToDo: advance time

        console.log("");
        console.log("====================================");
        console.log("             WITHDRAW");
        console.log("====================================");
        console.log("");

        // withdraw tokens
        on(toChainId);
        uint256 window = 0;
        
        toLiquidityHub.withdrawClaims(transferBondedEvent.tokenBusId, bonder1, window);

        printBalance(toChainId, bonder1);
        printBalance(toChainId, address(toLiquidityHub));
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
        returns (TransferSentEvent memory)
    {
        vm.startPrank(from);
        LiquidityHub fromLiquidityHub = liquidityHubForChainId[fromChainId];
        bytes32 tokenBusId = fromLiquidityHub.getTokenBusId(fromChainId, IERC20(address(fromToken)), toChainId, IERC20(address(toToken)));
        uint256[] memory destinations = new uint256[](1);
        destinations[0] = toChainId;
        uint256 fee = fromLiquidityHub.getFee(destinations);

        fromToken.approve(address(fromLiquidityHub), amount);
        vm.recordLogs();
        fromLiquidityHub.send{value: fee}(tokenBusId, to, amount, minAmountOut);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        TransferSentEvent[] memory transferSentEvents = logs.getTransferSentEvents();
        TransferSentEvent memory transferSentEvent = transferSentEvents[0];
        vm.stopPrank();

        return transferSentEvent;
    }

    function bond(address bonder, TransferSentEvent memory transferSentEvent) internal crossChainBroadcast returns (TransferBondedEvent memory) {
        vm.startPrank(bonder);
        uint256 fromChainId = transferSentEvent.fromChainId;
        on(fromChainId);
        LiquidityHub fromLiquidityHub = liquidityHubForChainId[fromChainId];
        bytes32 tokenBusId = transferSentEvent.tokenBusId;

        ( , IERC20 fromToken, uint256 toChainId, IERC20 toToken) = fromLiquidityHub.getTokenBusInfo(tokenBusId);

        on(toChainId);
        LiquidityHub toLiquidityHub = liquidityHubForChainId[TO_CHAIN_ID];
        address to = transferSentEvent.to;
        uint256 amount = transferSentEvent.amount;
        uint256 minAmountOut = transferSentEvent.minAmountOut;

        toToken.approve(address(toLiquidityHub), amount);
        vm.recordLogs();
        toLiquidityHub.bondTransfer(tokenBusId, to, amount, minAmountOut, amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        TransferBondedEvent[] memory transferBondedEvents = logs.getTransferBondedEvents();
        TransferBondedEvent memory transferBondedEvent = transferBondedEvents[0];
        vm.stopPrank();

        return transferBondedEvent;
    }
}
