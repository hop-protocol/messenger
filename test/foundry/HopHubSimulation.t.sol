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
                string.concat("Chain 0", SPOKE_CHAIN_ID_0.toString()),
                string.concat("Hop Hub", HUB_CHAIN_ID.toString()),
                string.concat("Chain 1", SPOKE_CHAIN_ID_1.toString())
            )
        );

        printTokenBalance(user1);
        printTokenBalance(bonder1);
    }

    function printTokenBalance(address account) internal crossChainBroadcast {
        string memory name = nameForAddress[account];

        on(SPOKE_CHAIN_ID_0);
        IERC20 token0 = tokenForChainId[SPOKE_CHAIN_ID_0];
        uint256 balance0 = token0.balanceOf(account);

        on(HUB_CHAIN_ID);
        IERC20 hubToken = tokenForChainId[HUB_CHAIN_ID];
        uint256 hubBalance = hubToken.balanceOf(account);

        on(SPOKE_CHAIN_ID_1);
        IERC20 toToken = tokenForChainId[SPOKE_CHAIN_ID_1];
        uint256 balance1 = toToken.balanceOf(account);

        printBalanceRow(name, balance0, hubBalance, balance1);
    }

    function printGatewayTokenBalances() internal crossChainBroadcast {
        on(SPOKE_CHAIN_ID_0);
        IERC20 token0 = tokenForChainId[SPOKE_CHAIN_ID_0];
        RailsGateway gateway0 = gatewayForChainId[SPOKE_CHAIN_ID_0];
        uint256 balance0 = token0.balanceOf(address(gateway0));

        on(HUB_CHAIN_ID);
        IERC20 hubToken = tokenForChainId[HUB_CHAIN_ID];
        RailsGateway hubGateway = gatewayForChainId[HUB_CHAIN_ID];
        uint256 hubBalance = hubToken.balanceOf(address(hubGateway));

        on(SPOKE_CHAIN_ID_1);
        IERC20 token1 = tokenForChainId[SPOKE_CHAIN_ID_1];
        RailsGateway gateway1 = gatewayForChainId[SPOKE_CHAIN_ID_1];
        uint256 balance1 = token1.balanceOf(address(gateway1));

        printBalanceRow("HopGateway", balance0, hubBalance, balance1);
    }

    function printBalanceRow(string memory name, uint256 balance0, uint256 balance1, uint256 balance2) internal {
        console.log(StringLib.toRow(name, balance0.format(18, 18), balance1.format(18, 18)), balance2.format(18, 18));
    }

    function setUp() public crossChainBroadcast {
        vm.deal(deployer, 10 * 1e18);
        vm.deal(user1, 10 * 1e18);
        vm.deal(bonder1, 10 * 1e18);

        chainIds.push(L1_CHAIN_ID);
        chainIds.push(HUB_CHAIN_ID);
        chainIds.push(SPOKE_CHAIN_ID_1);
        chainIds.push(SPOKE_CHAIN_ID_0);

        vm.startPrank(deployer);

        deployRails(L1_CHAIN_ID, chainIds);

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
            RailsGateway gateway = gatewayForChainId[chainId];
            IERC20 token = tokenForChainId[chainId];

            for (uint256 j = 0; j < chainIds.length; j++) {
                if (i == j) continue;
                uint256 counterpartChainId = chainIds[j];
                IERC20 counterpartToken = tokenForChainId[counterpartChainId];
                bytes32 pathId = gateway.initPath(
                    token,
                    counterpartChainId,
                    counterpartToken,
                    IMessageDispatcher(address(dispatcherForChainId[chainId])),
                    IMessageExecutor(address(executorForChainId[chainId])),
                    10_000_000_000 * ONE_TKN
                );
            }
        }

        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 1 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e20));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e15));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 20 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 39 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 52 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 15 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 87 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 34 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 16 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e24));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 41 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 87 * 1e4));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 22 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 22 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 22 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 41 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 71 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 34 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e15));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 52 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 15 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 87 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 34 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 16 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 46 * 1e24));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 39 * 1e24));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 41 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 87 * 1e4));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 41 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 71 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 34 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 9 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e20));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e15));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 17 * 1e24));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 20 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 39 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e8));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 22 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 22 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 22 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 47 * 1e9));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e17));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 47 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 77 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 46 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 82 * 1e16));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 76 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 21 * 1e14));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 45 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 12 * 1e24));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 92 * 1e15));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 18 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 59 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 88 * 1e23));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 93 * 1e21));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 1 * 1e19));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 5 * 1e22));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_1, SPOKE_CHAIN_ID_0, 370000 * 1e18));
        simTransfers.push(SimTransfer(SPOKE_CHAIN_ID_0, SPOKE_CHAIN_ID_1, 680000 * 1e18));

        vm.stopPrank();
    }

    function test_runHopHubSimulation() public crossChainBroadcast {
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

    function withdrawAll() internal broadcastOn(SPOKE_CHAIN_ID_0) {
        IERC20 hubToken = tokenForChainId[hubChainId];
        RailsGateway hubGateway = gatewayForChainId[hubChainId];
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 spokeChainId = chainIds[i];
            if (spokeChainId == hubChainId) continue;
            if (spokeChainId == l1ChainId) continue;

            IERC20 spokeToken = tokenForChainId[spokeChainId];
            RailsGateway spokeGateway = gatewayForChainId[spokeChainId];
            bytes32 pathId = spokeGateway.getPathId(hubChainId, hubToken, spokeChainId, spokeToken);

            console.log("pathId %s %s %x", hubChainId, spokeChainId, uint256(pathId));
            console.log("withdraw hub", hubChainId);
            withdrawAll(hubChainId, pathId, bonder1);
            console.log("withdraw spoke", spokeChainId);
            withdrawAll(spokeChainId, pathId, bonder1);
        }
    }

    function processSimTransfer(SimTransfer storage simTransfer) internal crossChainBroadcast() {
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
