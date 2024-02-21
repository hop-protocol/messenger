//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SlidingWindowLib, SlidingWindow} from "./SlidingWindowLib.sol";
import {IMessageDispatcher} from "../../ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../../ERC5164/IMessageExecutor.sol";
import {ICrossChainFees} from "../../messenger/interfaces/ICrossChainFees.sol";
import {CheckpointLib, Checkpoint, CheckpointChain} from "./CheckpointLib.sol";
import {ILiquidityHub} from "../interfaces/ILiquidityHub.sol";
import {StakingRegistry} from "../StakingRegistry.sol";

import {console} from "forge-std/console.sol";

struct Path {
    bytes32 pathId;
    IERC20 token;
    IERC20 counterpartToken;
    uint256 counterpartChainId;
    IMessageDispatcher dispatcher;
    IMessageExecutor executor;
    StakingRegistry stakingRegistry;
    uint256 rateDelta;

    // Checkpoints
    CheckpointChain checkpoints;
    CheckpointChain claims;

    // Send
    uint256 feeBalance;
    uint256 nonce;

    mapping(bytes32 => uint256) claimPostedAt;
    
    // Withdrawal
    mapping(address => uint256) balance;
    mapping(address => uint256) withdrawn;
    mapping(address => SlidingWindow) withdrawable;
    mapping(address => SlidingWindow) minTotalSent;
}

library PathLib {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using SlidingWindowLib for SlidingWindow;
    using PathLib for Path;
    using CheckpointLib for CheckpointChain;

    event TransferSent(
        bytes32 indexed pathId,
        bytes32 indexed checkpointId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent,
        uint256 nonce,
        bytes32 attestedCheckpoint
    );

    event TransferBonded(
        bytes32 indexed claimId,
        bytes32 indexed pathId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent
    );

    function initialize(
        Path storage path,
        bytes32 pathId,
        IERC20 token,
        uint256 counterpartChainId,
        IERC20 counterpartToken,
        IMessageDispatcher dispatcher,
        IMessageExecutor executor,
        StakingRegistry stakingRegistry,
        uint256 rateDelta
    )
        public
    {
        require(path.pathId == bytes32(0), "PathLib: Path already initialized");
        bytes32 expectedFlummId = PathLib.getPathId(block.chainid, token, counterpartChainId, counterpartToken);
        require(pathId == expectedFlummId, "PathLib: unexpected Path Id");

        path.pathId = pathId;
        path.token = token;
        path.counterpartChainId = counterpartChainId;
        path.counterpartToken = counterpartToken;
        path.dispatcher = dispatcher;
        path.executor = executor;
        path.stakingRegistry = stakingRegistry;
        path.rateDelta = rateDelta;
    }

    function send(
        Path storage path,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        bytes32 attestedCheckpoint
    )
        internal
    {
        uint256 attestedTotalSent;
        if (attestedCheckpoint != bytes32(0)) {
            attestedTotalSent = path.claims.getCheckpointData(attestedCheckpoint).totalSent;
        }
        uint256 adjustedAmount;
        uint256 totalSent;
        {
            // Credit Path
            uint256 fee = path.calcFee(amount, attestedTotalSent);
            adjustedAmount = amount - fee;
            require(adjustedAmount >= minAmountOut, "PathLib: insufficient amount out");
            totalSent = path.checkpoints.getTotalSent() + adjustedAmount;

            path.feeBalance += fee;
        }

        bytes32 checkpointId;
        {
            uint256 nonce = path.nonce;
            path.nonce++;


            bytes32 claimId = getClaimId(
                path.pathId,
                to,
                adjustedAmount,
                minAmountOut,
                totalSent,
                nonce,
                attestedCheckpoint
            );

            checkpointId = path.checkpoints.push(claimId, totalSent);

            emit TransferSent(
                path.pathId,
                checkpointId,
                to,
                adjustedAmount,
                minAmountOut,
                totalSent,
                nonce,
                attestedCheckpoint
            );
        }


        // Send message
        bytes memory confirmCheckpointData = abi.encodeWithSelector(ILiquidityHub.confirmCheckpoint.selector, checkpointId);
        path.dispatcher.dispatchMessage{value: msg.value}(path.counterpartChainId, address(this), confirmCheckpointData);

        // Collect tokens
        IERC20(path.token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function postClaim(
        Path storage path,
        bytes32 claimId,
        bytes32 checkpointId,
        uint256 totalSent
    )
        internal
        returns (bool)
    {
        path.claimPostedAt[claimId] = block.timestamp;
        bytes32 calculatedCheckpointId = path.claims.push(claimId, totalSent);

        require(checkpointId == calculatedCheckpointId, "PathLib: invalid checkpoint");
    }

    function removeClaim(
        Path storage path,
        bytes32 checkpointId,
        uint256 nonce
    )
        internal
    {
        path.claims.pop(nonce, checkpointId);
    }

    function bond(
        Path storage path,
        bytes32 checkpointId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent,
        uint256 nonce,
        bytes32 attestedCheckpoint
    )
        internal
    {
        // ToDo: Check stake balance
        // uint256 stakeBalance = path.stakingRegistry.getStakedBalance("Bonder", msg.sender);
        // require(stakeBalance >= minBonderStake, "PathLib: insufficient stake");

        if (attestedCheckpoint != bytes32(0)) {
            require(path.checkpoints.isCheckpoint(attestedCheckpoint), "PathLib: attested checkpoint mismatch");
        }

        bytes32 claimId = getClaimId(
            path.pathId,
            to,
            amount,
            minAmountOut,
            totalSent,
            nonce,
            attestedCheckpoint
        );

        uint256 bonus = path.calcBonus(amount, totalSent, path.checkpoints.getTotalSent());
        uint256 adjustedAmount = amount + bonus;

        path.postClaim(claimId, checkpointId, totalSent);

        uint256 balance = path.balance[msg.sender] + adjustedAmount;
        path.balance[msg.sender] = balance;
        path.withdrawable[msg.sender].set(block.timestamp, balance);
        path.minTotalSent[msg.sender].set(block.timestamp, totalSent);

        IERC20(path.token).transferFrom(msg.sender, to, adjustedAmount);

        emit TransferBonded(
            claimId,
            path.pathId,
            to,
            amount,
            minAmountOut,
            totalSent
        );
    }

    function withdraw(Path storage path, uint256 amount, uint256 time) internal {
        uint256 withdrawable = path.getWithdrawableBalance(msg.sender, time);
        require(withdrawable >= amount, "PathLib: insufficient withdrawable balance");

        path.withdrawn[msg.sender] += amount;
        IERC20(path.token).safeTransfer(msg.sender, amount);
    }

    function withdrawAll(Path storage path, uint256 time) internal {
        uint256 amount = path.getWithdrawableBalance(msg.sender, time);

        path.withdrawn[msg.sender] += amount;
        IERC20(path.token).safeTransfer(msg.sender, amount);
    }

    // on deposit
    function calcFee(Path storage path, uint256 amount, uint256 attestedTotalSent) internal view returns (uint256) {
        // if there is enough surplus for the claim, return 0 fee
        uint256 totalSent = path.checkpoints.totalSent();
        if (attestedTotalSent > totalSent + amount) return 0;

        uint256 startDeficit = attestedTotalSent - totalSent;
        uint256 endDeficit = 0;
        if (startDeficit > amount) {
            endDeficit = startDeficit - amount;
        }

        uint256 avgDeficit = (startDeficit + endDeficit) / 2;
        uint256 rate = avgDeficit * path.rateDelta / 10e18;
        uint256 fee = amount * rate / 10e18;

        return fee;
    }

    // on withdrawal
    function calcBonus(Path storage path, uint256 amount, uint256 totalSent, uint256 attestedTotalSent) internal view returns (uint256) {
        // if liquidity was freed, calculate the bonus
        if (totalSent >= attestedTotalSent) return 0;

        uint256 endDeficit = attestedTotalSent - totalSent;
        uint256 startDeficit = 0;
        if (endDeficit > amount) {
            startDeficit = endDeficit - amount;
        }

        uint256 avgDeficit = (startDeficit + endDeficit) / 2;
        uint256 rate = avgDeficit * path.rateDelta / 10e18;
        uint256 bonus = amount * rate / 10e18;

        return bonus;
    }

    function getPathId(uint256 chainId0, IERC20 token0, uint256 chainId1, IERC20 token1) internal view returns (bytes32) {
        bool isAssending = chainId0 < chainId1;

        uint256 chainIdA = isAssending ? chainId0 : chainId1;
        uint256 chainIdB = isAssending ? chainId1 : chainId0;
        IERC20 tokenA = isAssending ? token0 : token1;
        IERC20 tokenB = isAssending ? token1 : token0;

        return keccak256(abi.encodePacked(chainIdA, tokenA, chainIdB, tokenB));
    }

    function getHead(Path storage path) internal view returns (bytes32) {
        uint256 chainLength = path.checkpoints.checkpoints.length;
        if (chainLength == 0) return bytes32(0);
        return path.checkpoints.getCheckpointData(chainLength - 1).checkpointId;
    }

    function getWithdrawableBalance(Path storage path, address bonder, uint256 time) internal view returns (uint256) {
        uint256 minTotalSent = path.minTotalSent[bonder].get(time);
        uint256 withdrawable = path.withdrawable[bonder].get(time);
        require(minTotalSent != 0, "PathLib: Invalid time");
        require(withdrawable != 0, "PathLib: Invalid time");

        uint256 totalSent = path.checkpoints.totalSent();
        uint256 withdrawn = path.withdrawn[bonder];
        if (totalSent < minTotalSent || withdrawable < withdrawn) {
            return 0;
        } else {
            return withdrawable - withdrawn;
        }
    }

    function getClaimId(
        bytes32 pathId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent,
        uint256 nonce,
        bytes32 attestedCheckpoint
    )
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                pathId,
                to,
                amount,
                minAmountOut,
                totalSent,
                nonce,
                attestedCheckpoint
            )
        );
    }

    function getCheckpointId(
        bytes32 previousHash,
        bytes32 claimId,
        uint256 totalSent
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(previousHash, claimId, totalSent));
    }

    function getFee(Path storage path) internal view returns (uint256) {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = path.counterpartChainId;
        return ICrossChainFees(address(path.dispatcher)).getFee(chainIds);
    }
}