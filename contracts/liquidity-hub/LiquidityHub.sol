//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SlidingWindowLib, SlidingWindow} from "./libraries/SlidingWindowLib.sol";
import {TokenBusLib, TokenBus} from "./libraries/TokenBusLib.sol";
import {IMessageDispatcher} from "../ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../ERC5164/IMessageExecutor.sol";
import {ICrossChainFees} from "../messenger/interfaces/ICrossChainFees.sol";
import {StakingRegistry} from "./StakingRegistry.sol";

contract LiquidityHub is StakingRegistry, ICrossChainFees {
    using SafeERC20 for IERC20;
    using TokenBusLib for TokenBus;
    using SlidingWindowLib for SlidingWindow;

    IMessageDispatcher public dispatcher;
    IMessageExecutor public executor;

    mapping(bytes32 => TokenBus) internal tokenBuses;

    IERC20 public hopToken;
    uint256 public minBonderStake = 100_000 * 10e18;

    event TransferSent(
        bytes32 indexed claimId,
        bytes32 indexed tokenBusId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 sourceClaimsSent,
        uint256 bonus
    );

    event TransferBonded(
        bytes32 indexed claimId,
        bytes32 indexed tokenBusId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 sourceClaimsSent,
        uint256 fee
    );

    constructor(
        IMessageDispatcher _dispatcher,
        IMessageExecutor _executor
    ) {
        dispatcher = _dispatcher;
        executor = _executor;
    }

    function initTokenBus(
        IERC20 token,
        uint256 counterpartChainId,
        IERC20 counterpartToken,
        uint256 rateDelta
    )
        public
        returns
        (bytes32)
    {
        bytes32 tokenBusId = TokenBusLib.getTokenBusId(block.chainid, token, counterpartChainId, counterpartToken);
        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        tokenBus.token = token;
        tokenBus.counterpartChainId = counterpartChainId;
        tokenBus.counterpartToken = counterpartToken;
        tokenBus.rateDelta = rateDelta;

        return tokenBusId;
    }

    function send(
        bytes32 tokenBusId,
        address to,
        uint256 amount,
        uint256 minAmountOut
    )
        external
        payable
    {
        // Credit token bus
        TokenBus storage tokenBus = tokenBuses[tokenBusId];

        uint256 bonus = tokenBus.calcBonus(amount);
        tokenBus.feeBalance -= bonus;
        uint256 adjustedAmount = amount + bonus;

        uint256 sourceClaimsSent = tokenBus.claimsSent + amount;
        tokenBus.claimsSent = sourceClaimsSent;
        bytes32 claimId = getClaimId(
            tokenBusId,
            to,
            adjustedAmount,
            minAmountOut,
            sourceClaimsSent
        );

        // Send message
        bytes memory confirmClaimData = abi.encodeWithSelector(this.confirmClaim.selector, claimId);
        dispatcher.dispatchMessage{value: msg.value}(tokenBus.counterpartChainId, address(this), confirmClaimData);

        IERC20(tokenBus.token).safeTransferFrom(msg.sender, address(this), amount);

        emit TransferSent(
            claimId,
            tokenBusId,
            to,
            adjustedAmount,
            minAmountOut,
            sourceClaimsSent,
            bonus
        );
    }

    function bond(
        bytes32 tokenBusId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 sourceClaimsSent
    )
        external
    {
        // ToDo: Replay protection

        TokenBus storage tokenBus = tokenBuses[tokenBusId];

        uint256 stakeBalance = getStakedBalance("Bonder", msg.sender);
        require(stakeBalance >= minBonderStake, "LiquidityHub: insufficient stake");

        bytes32 claimId = getClaimId(
            tokenBusId,
            to,
            amount,
            minAmountOut,
            sourceClaimsSent
        );

        uint256 fee = tokenBus.calcFee(amount, sourceClaimsSent);
        if (tokenBus.claimPosted[claimId]) {
            tokenBus.pendingBalances[to].sub(block.timestamp, amount);
            tokenBus.balance[to] -= amount;    
        } else {
            fee = tokenBus.calcFee(amount, sourceClaimsSent);
        }

        uint256 adjustedAmount = amount - fee;

        address bonder = msg.sender;
        tokenBus.pendingBalances[bonder].add(block.timestamp, adjustedAmount);
        tokenBus.balance[bonder] += adjustedAmount;
        tokenBus.minClaimsSent[bonder].set(block.timestamp, sourceClaimsSent);

        tokenBus.claimPosted[claimId] = true;
        tokenBus.claimsReceived += amount;
        tokenBus.feeBalance += fee;

        IERC20(tokenBus.token).transferFrom(bonder, to, adjustedAmount);

        emit TransferBonded(
            claimId,
            tokenBusId,
            to,
            amount,
            minAmountOut,
            sourceClaimsSent,
            fee
        );
    }

    function postClaim(
        bytes32 tokenBusId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 sourceClaimsSent
    )
        external
    {
        bytes32 claimId = getClaimId(
            tokenBusId,
            to,
            amount,
            minAmountOut,
            sourceClaimsSent
        );

        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        require(!tokenBus.claimPosted[claimId], "LiquidityHub: Claim already posted");
        tokenBus.claimPosted[claimId] = true;

        tokenBus.claimsReceived += amount;

        // Credit recipient
        address bonder = address(0); // ToDo
        address recipient = bonder == address(0) ? to : bonder;

        tokenBus.pendingBalances[recipient].add(block.timestamp, amount);
        tokenBus.balance[recipient] += amount;
        tokenBus.minClaimsSent[recipient].set(block.timestamp, sourceClaimsSent);
    }

    function withdrawClaims(bytes32 tokenBusId, address recipient, uint256 window) external {
        // ToDo: set min window age
        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        uint256 withdrawalAmount = tokenBus.getWithdrawableBalance(recipient, window);
        tokenBus.balance[recipient] -= withdrawalAmount;
        IERC20(tokenBus.token).transfer(recipient, withdrawalAmount);
    }

    function challengeClaim() external {

    }

    function confirmClaim(bytes32 claim) external {

    }

    function resolveChallenge() external {

    }

    function getWithdrawableBalance(bytes32 tokenBusId, address recipient, uint256 window) public view returns (uint256) {
        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        return tokenBus.getWithdrawableBalance(recipient, window);
    }

    function getClaimId(
        bytes32 tokenBusId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 sourceClaimsSent
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                tokenBusId,
                to,
                amount,
                minAmountOut,
                sourceClaimsSent
            )
        );
    }

    function getTokenBusId(uint256 chainId0, IERC20 token0, uint256 chainId1, IERC20 token1) external pure returns (bytes32) {
        return TokenBusLib.getTokenBusId(chainId0, token0, chainId1, token1);
    }

    function getFee(uint256[] calldata chainIds) external view returns (uint256) {
        return ICrossChainFees(address(dispatcher)).getFee(chainIds);
    }

    function getTokenBusInfo(bytes32 tokenBusId) external view returns (uint256, IERC20, uint256, IERC20) {
        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        return (block.chainid, tokenBus.token, tokenBus.counterpartChainId, tokenBus.counterpartToken);
    }
}

