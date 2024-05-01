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
    HUB_CHAIN_ID,
    SPOKE_CHAIN_ID_0,
    SPOKE_CHAIN_ID_1,
    ONE_TKN
} from "./libraries/Constants.sol";
import {StringLib} from "./libraries/StringLib.sol";

import {console} from "forge-std/console.sol";

struct SimTransfer {
    uint256 fromChainId;
    uint256 toChainId;
    uint256 amount;
}

contract RailsSimulation_Test is RailsFixture {
    using MessengerEventParser for MessengerEvents;
    using RailsGatewayEventParser for Vm.Log[];
    using RailsGatewayEventParser for TransferSentEvent;
    using RailsGatewayEventParser for TransferBondedEvent;
    using RailsGatewayEventParser for RailsGatewayEvents;
    using StringLib for string;
    using StringLib for uint256;
    using StringLib for string[];

    uint256[] public chainIds;
    mapping(uint256 => IERC20) public tokenForChainId;
    // mapping(uint256 => RailsGateway) public gatewayForChainId;

    uint256 public constant AMOUNT = 100 * 1e18;
    uint256 public constant MIN_AMOUNT_OUT = 99 * 1e18;
    uint256 public constant FROM_CHAIN_ID = 11155111;
    uint256 public constant TO_CHAIN_ID = 11155420;

    mapping(address => string) public nameForAddress;

    address public constant deployer = address(1);
    address public constant user1 = address(2);
    address public constant bonder1 = address(3);

    // RailsGatewayEvents railsEvents;

    SimTransfer[] public simTransfers;

    // mapping(uint256 => uint256) totalSent;
    // mapping(uint256 => uint256) totalBonded;
    // mapping(uint256 => uint256) totalAttestationFees;
    // mapping(uint256 => uint256) totalWithdrawn;
    // mapping(uint256 => uint256) totalRate;
    // mapping(uint256 => uint256) lastBondTimestamp;
    // mapping(uint256 => MessageSentEvent) latestMessageSent;


    constructor() {
        nameForAddress[deployer] = "DEPLOYER";
        nameForAddress[user1] = "USER 1";
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
        console.log(
            StringLib.toHeader(
                "Name",
                string.concat("From Chain ", FROM_CHAIN_ID.toString()),
                string.concat("To Chain ", TO_CHAIN_ID.toString())
            )
        );

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

        printBalanceRow(name, fromBalance, toBalance);
    }

    function printGatewayTokenBalances() internal crossChainBroadcast {
        on(FROM_CHAIN_ID);
        IERC20 fromToken = tokenForChainId[FROM_CHAIN_ID];
        RailsGateway fromGateway = gatewayForChainId[FROM_CHAIN_ID];
        uint256 fromBalance = fromToken.balanceOf(address(fromGateway));

        on(TO_CHAIN_ID);
        IERC20 toToken = tokenForChainId[TO_CHAIN_ID];
        RailsGateway toGateway = gatewayForChainId[TO_CHAIN_ID];
        uint256 toBalance = toToken.balanceOf(address(toGateway));

        printBalanceRow("HopGateway", fromBalance, toBalance);
    }

    function printBalanceRow(string memory name, uint256 balance0, uint256 balance1) internal {
        console.log(StringLib.toRow(name, balance0.format(18, 18), balance1.format(18, 18)));
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
            MockToken(address(token)).deal(address(user1), 1e12 * 1e18);
            MockToken(address(token)).deal(address(bonder1), 1e12 * 1e18);
            tokenForChainId[chainId] = token;
        }

        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            on(chainId);
            RailsGateway gateway = new RailsGateway();
            gatewayForChainId[chainId] = gateway;
            IERC20 token = tokenForChainId[chainId];

            for (uint256 j = 0; j < chainIds.length; j++) {
                uint256 counterpartChainId = chainIds[j];
                if (counterpartChainId == chainId) continue;
                IERC20 counterpartToken = tokenForChainId[counterpartChainId];
                bytes32 pathId = gateway.initPath(
                    token,
                    counterpartChainId,
                    counterpartToken,
                    IMessageDispatcher(address(dispatcherForChainId[chainId])),
                    IMessageExecutor(address(executorForChainId[chainId])),
                    10_000_000_000 * ONE_TKN,
                    10_000_000_000 * ONE_TKN,
                    200000000000000
                );
            }
        }

        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e20));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e22));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e23));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e21));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e15));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 20 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 39 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 52 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 15 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 87 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 34 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 16 * 1e14));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e24));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e23));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e21));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 41 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 87 * 1e4));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e9));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 22 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 22 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 22 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e22));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e23));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e23));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 41 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 71 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 34 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e9));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e22));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e23));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e23));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e21));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e22));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e23));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e23));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e23));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e23));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e15));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e23));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 52 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 15 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 87 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 34 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 16 * 1e14));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e21));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 46 * 1e24));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e23));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e21));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 39 * 1e24));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 41 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 87 * 1e4));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e23));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e23));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 41 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 71 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 34 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e9));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e21));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e21));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 9 * 1e22));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e23));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e22));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e20));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e15));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 17 * 1e24));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 20 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 39 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e21));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e8));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e19));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e23));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e17));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 22 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 22 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 22 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 47 * 1e9));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e17));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 47 * 1e18));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 77 * 1e22));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 46 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 82 * 1e16));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 76 * 1e14));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 21 * 1e14));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 45 * 1e22));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 12 * 1e24));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 92 * 1e15));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 18 * 1e22));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 59 * 1e23));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 88 * 1e23));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 93 * 1e21));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 1 * 1e19));
        simTransfers.push(SimTransfer(TO_CHAIN_ID, FROM_CHAIN_ID, 5 * 1e22));
        simTransfers.push(SimTransfer(FROM_CHAIN_ID, TO_CHAIN_ID, 28514481046626596013834));

        vm.stopPrank();
    }

    function test_runSimulation() public crossChainBroadcast {
        console.log("Running Simulation");
        console.log("");

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

        relayMessage(latestMessageSent[FROM_CHAIN_ID]);
        relayMessage(latestMessageSent[TO_CHAIN_ID]);

        console.log("");
        console.log("Bonder withdrawing...");
        console.log("");

        withdrawAll();

        printTokenBalances();
        printGatewayTokenBalances();

        uint256 _totalSent = totalSent[FROM_CHAIN_ID] + totalSent[TO_CHAIN_ID];
        uint256 _totalBonded = totalBonded[FROM_CHAIN_ID] + totalBonded[TO_CHAIN_ID];
        uint256 _totalAttestationFees = totalAttestationFees[FROM_CHAIN_ID] + totalAttestationFees[TO_CHAIN_ID];
        uint256 _totalWithdrawn = totalWithdrawn[FROM_CHAIN_ID] + totalWithdrawn[TO_CHAIN_ID];
        uint256 _avgRate = (totalRate[FROM_CHAIN_ID] + totalRate[TO_CHAIN_ID]) / simTransfers.length;

        console.log("");
        console.log(StringLib.toRow("totalSent", _totalSent.formatDollar(18, 18)));
        console.log(StringLib.toRow("totalBonded", _totalBonded.formatDollar(18, 18)));
        console.log(StringLib.toRow("totalAttestationFees", _totalAttestationFees.formatDollar(18, 18)));
        console.log(StringLib.toRow("totalWithdrawn", _totalWithdrawn.formatDollar(18, 18)));
        console.log("");

        // IERC20 fromToken = tokenForChainId[FROM_CHAIN_ID];
        // IERC20 toToken = tokenForChainId[TO_CHAIN_ID];
        // bytes32 pathId = fromRailsGateway.getPathId(FROM_CHAIN_ID, fromToken, TO_CHAIN_ID, toToken);
        // withdrawAll(FROM_CHAIN_ID, pathId);
        // withdrawAll(TO_CHAIN_ID, pathId);

        // printTokenBalance(FROM_CHAIN_ID, address(gatewayForChainId[FROM_CHAIN_ID]));
        // printTokenBalance(TO_CHAIN_ID, address(gatewayForChainId[TO_CHAIN_ID]));
    }

    function withdrawAll() internal broadcastOn(FROM_CHAIN_ID) {
        IERC20 fromToken = tokenForChainId[FROM_CHAIN_ID];
        IERC20 toToken = tokenForChainId[TO_CHAIN_ID];
        RailsGateway fromRailsGateway = gatewayForChainId[FROM_CHAIN_ID];
        bytes32 pathId = fromRailsGateway.getPathId(FROM_CHAIN_ID, fromToken, TO_CHAIN_ID, toToken);

        withdrawAll(FROM_CHAIN_ID, pathId, bonder1);
        withdrawAll(TO_CHAIN_ID, pathId, bonder1);
    }

    function processSimTransfer(SimTransfer storage simTransfer) internal crossChainBroadcast() {
        IERC20 fromToken = tokenForChainId[simTransfer.fromChainId];
        IERC20 toToken = tokenForChainId[simTransfer.toChainId];
        uint256 minAmountOut = 0;

        (
            TransferSentEvent storage transferSentEvent,
            MessageSentEvent storage messageSentEvent
        ) = send(
            user1,
            simTransfer.fromChainId,
            fromToken,
            simTransfer.toChainId,
            toToken,
            user1,
            simTransfer.amount,
            minAmountOut
        );
        transferSentEvent.printEvent();

        on(simTransfer.toChainId);
        uint256 beforeBalance = toToken.balanceOf(user1);
        TransferBondedEvent storage transferBondedEvent = bond(bonder1, transferSentEvent);
        uint256 afterBalance = toToken.balanceOf(user1);

        uint256 sent = transferSentEvent.amount;
        uint256 received = afterBalance - beforeBalance;

        uint256 rate = received * ONE_TKN / transferSentEvent.amount;
        totalRate[simTransfer.fromChainId] += rate;

        transferBondedEvent.printEvent();

        latestMessageSent[simTransfer.fromChainId] = messageSentEvent;
    }
}
