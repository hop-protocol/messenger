//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SlidingWindowLib, SlidingWindow} from "./libraries/SlidingWindowLib.sol";
import {TokenBusLib, TokenBus} from "./libraries/TokenBusLib.sol";
import {IMessageDispatcher} from "../ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../ERC5164/IMessageExecutor.sol";
import {ICrossChainFees} from "../messenger/interfaces/ICrossChainFees.sol";

contract LiquidityHub is ICrossChainFees {
    using SafeERC20 for IERC20;
    using TokenBusLib for TokenBus;
    using SlidingWindowLib for SlidingWindow;

    IMessageDispatcher public dispatcher;
    IMessageExecutor public executor;

    mapping(bytes32 => TokenBus) internal tokenBuses;

    event TransferSent(
        bytes32 indexed claimId,
        bytes32 indexed tokenBusId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 minClaimsSent
    );

    event TransferBonded(
        bytes32 indexed claimId,
        bytes32 indexed tokenBusId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 minClaimsSent
    );

    constructor(
        IMessageDispatcher _dispatcher,
        IMessageExecutor _executor
    ) {
        dispatcher = _dispatcher;
        executor = _executor;
    }

    function initTokenBus(IERC20 token, uint256 counterpartChainId, IERC20 counterpartToken) public returns (bytes32) {
        bytes32 tokenBusId = TokenBusLib.getTokenBusId(block.chainid, token, counterpartChainId, counterpartToken);
        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        tokenBus.token = token;
        tokenBus.counterpartChainId = counterpartChainId;
        tokenBus.counterpartToken = counterpartToken;

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
        // The minimum amount of claims to be sent by counterpart before this can be claimed.
        uint256 minClaimsSent = tokenBus.claimsSent + amount;
        tokenBus.claimsSent = minClaimsSent;

        bytes32 claimId = getClaimId(
            tokenBusId,
            to,
            amount,
            minAmountOut,
            minClaimsSent
        );

        // Send message
        bytes memory confirmClaimData = abi.encodeWithSelector(this.confirmClaim.selector, claimId);
        dispatcher.dispatchMessage{value: msg.value}(tokenBus.counterpartChainId, address(this), confirmClaimData);

        IERC20(tokenBus.token).safeTransferFrom(msg.sender, address(this), amount);

        emit TransferSent(
            claimId,
            tokenBusId,
            to,
            amount,
            minAmountOut,
            minClaimsSent
        );
    }

    function bondTransfer(
        bytes32 tokenBusId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 minClaimsSent
    )
        external
    {
        // ToDo: replay protection

        bytes32 claimId = getClaimId(
            tokenBusId,
            to,
            amount,
            minAmountOut,
            minClaimsSent
        );

        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        if (tokenBus.claimPosted[claimId]) {
            tokenBus.pendingBalances[to].sub(block.timestamp, amount);
            tokenBus.balance[to] -= amount;    
        }
        tokenBus.pendingBalances[msg.sender].add(block.timestamp, amount);
        tokenBus.balance[msg.sender] += amount;
        tokenBus.minClaimsSent[msg.sender].set(block.timestamp, minClaimsSent);

        tokenBus.claimPosted[claimId] = true;
        tokenBus.claimsReceived += amount;

        IERC20(tokenBus.token).transferFrom(msg.sender, to, amount);

        emit TransferBonded(
            claimId,
            tokenBusId,
            to,
            amount,
            minAmountOut,
            minClaimsSent
        );
    }

    function postClaim(
        bytes32 tokenBusId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 minClaimsSent
    )
        external
    {
        bytes32 claimId = getClaimId(
            tokenBusId,
            to,
            amount,
            minAmountOut,
            minClaimsSent
        );

        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        require(!tokenBus.claimPosted[claimId], "LiquidityHub: Claim already posted");
        tokenBus.claimPosted[claimId] = true;

        tokenBus.claimsReceived += amount;

        // Credit recipient
        address bonder = address(0); // ToDo
        address recipient = bonder == address(0) ? bonder : to;

        tokenBus.pendingBalances[recipient].add(block.timestamp, amount);
        tokenBus.balance[recipient] += amount;
        tokenBus.minClaimsSent[recipient].set(block.timestamp, minClaimsSent);
    }

    function withdrawClaims(bytes32 tokenBusId, address recipient, uint256 window) external {
        // ToDo: set min window age
        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        tokenBus.withdrawClaims(recipient, window);
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
        uint256 minClaimsSent
    )
        public
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                tokenBusId,
                to,
                amount,
                minAmountOut,
                minClaimsSent
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

