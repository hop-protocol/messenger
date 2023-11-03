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
        uint256 totalSent
    );

    event TransferBonded(
        bytes32 indexed claimId,
        bytes32 indexed tokenBusId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent
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
        uint256 minAmountOut,
        bytes32 attestedCheckpoint,
        uint256 attestedNonce,
        uint256 attestedTotalSent
    )
        external
        payable
    {
        // Credit token bus
        TokenBus storage tokenBus = tokenBuses[tokenBusId];

        uint256 fee = tokenBus.calcFee(amount, attestedTotalSent);
        uint256 adjustedAmount = amount - fee;
        uint256 totalSent = tokenBus.totalSent + adjustedAmount;
        uint256 nonce = tokenBus.checkpoints.length;
        bytes32 claimId = getClaimId(
            tokenBusId,
            to,
            adjustedAmount,
            minAmountOut,
            totalSent,
            nonce,
            attestedCheckpoint,
            attestedNonce,
            attestedTotalSent
        );
        bytes32 previousCheckpoint = tokenBus.checkpoints[nonce - 1];
        bytes32 thisCheckpoint = keccak256(abi.encodePacked(previousCheckpoint, claimId));

        tokenBus.feeBalance += fee;
        tokenBus.totalSent = totalSent;
        tokenBus.checkpoints.push(thisCheckpoint);
        tokenBus.totalSentAtCheckpoint[thisCheckpoint] = totalSent;

        uint256 pendingFreedAmount = 0;
        uint256 totalWithdrawable = tokenBus.totalWithdrawable + amount;
        if (attestedCheckpoint != bytes32(0)) {
            require(tokenBus.claimCheckpoints.length > attestedNonce, "LiquidityHub: attested nonce to high");
            require(tokenBus.claimCheckpoints[attestedNonce] == attestedCheckpoint, "LiquidityHub: attested checkpoint mismatch");
            uint256 totalClaimsAtCheckpoint = tokenBus.totalClaimsAtCheckpoint[attestedCheckpoint];
            require(totalClaimsAtCheckpoint == attestedTotalSent, "LiquidityHub: attested checkpoint mismatch");

            if (totalClaimsAtCheckpoint < totalWithdrawable) {
                pendingFreedAmount =  totalWithdrawable - totalClaimsAtCheckpoint;
            }
        }

        tokenBus.totalWithdrawable = totalWithdrawable;
        tokenBus.pendingWithdrawable.add(block.timestamp, pendingFreedAmount);

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
            totalSent
        );
    }

    function bond(
        bytes32 tokenBusId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent,
        uint256 nonce,
        bytes32 attestedCheckpoint,
        uint256 attestedNonce,
        uint256 attestedTotalSent
    )
        external
    {
        // ToDo: Replay protection
        TokenBus storage tokenBus = tokenBuses[tokenBusId];

        uint256 stakeBalance = getStakedBalance("Bonder", msg.sender);
        require(stakeBalance >= minBonderStake, "LiquidityHub: insufficient stake");
        require(tokenBus.checkpoints[attestedNonce] == attestedCheckpoint, "LiquidityHub: attested checkpoint mismatch");
        require(tokenBus.totalSentAtCheckpoint[attestedCheckpoint] == attestedTotalSent, "attested total sent mismatch");
        require(tokenBus.claimCheckpoints.length + 1 == nonce, "LiquidityHub: bond nonce mismatch");

        bytes32 claimId = getClaimId(
            tokenBusId,
            to,
            amount,
            minAmountOut,
            totalSent,
            nonce,
            attestedCheckpoint,
            attestedNonce,
            attestedTotalSent
        );

        uint256 bonus = tokenBus.calcBonus(amount, totalSent, tokenBus.totalSent);
        uint256 adjustedAmount = amount + bonus;
        uint256 claimPostedAt = block.timestamp;
        if (tokenBus.claimPostedAt[claimId] == 0) {
            tokenBus.claimPostedAt[claimId] = claimPostedAt;
            tokenBus.feeBalance -= bonus;
            tokenBus.totalClaims += adjustedAmount;

            bytes32 previousBondedCheckpoint = tokenBus.checkpoints[nonce - 1];
            bytes32 nextBondedCheckpoint = keccak256(abi.encodePacked(previousBondedCheckpoint, claimId));
            tokenBus.claimCheckpoints.push(nextBondedCheckpoint);
            tokenBus.totalClaimsAtCheckpoint[nextBondedCheckpoint] += totalSent;
        } else {
            claimPostedAt = tokenBus.claimPostedAt[claimId];
            tokenBus.pendingBalances[to].sub(claimPostedAt, adjustedAmount);
            tokenBus.balance[to] -= adjustedAmount;
        }

        tokenBus.pendingBalances[msg.sender].add(claimPostedAt, adjustedAmount);
        tokenBus.balance[msg.sender] += adjustedAmount;
        tokenBus.minTotalSent[msg.sender].set(claimPostedAt, totalSent);

        IERC20(tokenBus.token).transferFrom(msg.sender, to, adjustedAmount);

        emit TransferBonded(
            claimId,
            tokenBusId,
            to,
            amount,
            minAmountOut,
            totalSent
        );
    }

    function postClaim(
        bytes32 tokenBusId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent,
        uint256 nonce,
        bytes32 attestedCheckpoint,
        uint256 attestedNonce,
        uint256 attestedTotalSent
    )
        external
    {
        bytes32 claimId = getClaimId(
            tokenBusId,
            to,
            amount,
            minAmountOut,
            totalSent,
            nonce,
            attestedCheckpoint,
            attestedNonce,
            attestedTotalSent
        );

        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        require(tokenBus.claimPostedAt[claimId] == 0, "LiquidityHub: Claim already posted");
        tokenBus.claimPostedAt[claimId] = block.timestamp;

        uint256 bonus = tokenBus.calcBonus(amount, totalSent, tokenBus.totalSent);
        uint256 adjustedAmount = amount + bonus;
        tokenBus.feeBalance -= bonus;
        tokenBus.totalClaims += adjustedAmount;

        // Credit recipient
        tokenBus.pendingBalances[to].add(block.timestamp, amount);
        tokenBus.balance[to] += amount;
        tokenBus.minTotalSent[to].set(block.timestamp, totalSent);
    }

    function withdrawClaims(bytes32 tokenBusId, address recipient, uint256 window) external {
        // ToDo: set min window age
        TokenBus storage tokenBus = tokenBuses[tokenBusId];
        uint256 withdrawalAmount = tokenBus.getWithdrawableBalance(recipient, window);
        tokenBus.balance[recipient] -= withdrawalAmount;
        tokenBus.totalWithdrawn += withdrawalAmount;
        IERC20(tokenBus.token).safeTransfer(recipient, withdrawalAmount);
    }

    function replaceClaim() external {

    }

    function confirmClaim(bytes32 claim) external {

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
        uint256 totalSent,
        uint256 nonce,
        bytes32 attestedCheckpoint,
        uint256 attestedNonce,
        uint256 attestedTotalSent
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
                totalSent,
                nonce,
                attestedCheckpoint,
                attestedNonce,
                attestedTotalSent
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
