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

struct FLUMM {
    bytes32 flummId;
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

library FLUMMLib {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using SlidingWindowLib for SlidingWindow;
    using FLUMMLib for FLUMM;
    using CheckpointLib for CheckpointChain;

    event TransferSent(
        bytes32 indexed flummId,
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
        bytes32 indexed flummId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent
    );

    function initialize(
        FLUMM storage flumm,
        bytes32 flummId,
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
        require(flumm.flummId == bytes32(0), "FLUMMLib: FLUMM already initialized");
        bytes32 expectedFlummId = FLUMMLib.getFLUMMId(block.chainid, token, counterpartChainId, counterpartToken);
        require(flummId == expectedFlummId, "FLUMMLib: unexpected FLUMM Id");

        flumm.flummId = flummId;
        flumm.token = token;
        flumm.counterpartChainId = counterpartChainId;
        flumm.counterpartToken = counterpartToken;
        flumm.dispatcher = dispatcher;
        flumm.executor = executor;
        flumm.stakingRegistry = stakingRegistry;
        flumm.rateDelta = rateDelta;
    }

    function send(
        FLUMM storage flumm,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        bytes32 attestedCheckpoint
    )
        internal
    {
        uint256 attestedTotalSent;
        if (attestedCheckpoint != bytes32(0)) {
            attestedTotalSent = flumm.claims.getCheckpointData(attestedCheckpoint).totalSent;
        }
        uint256 adjustedAmount;
        uint256 totalSent;
        {
            // Credit FLUMM
            uint256 fee = flumm.calcFee(amount, attestedTotalSent);
            adjustedAmount = amount - fee;
            require(adjustedAmount >= minAmountOut, "FLUMMLib: insufficient amount out");
            totalSent = flumm.checkpoints.getTotalSent() + adjustedAmount;

            flumm.feeBalance += fee;
        }

        bytes32 checkpointId;
        {
            uint256 nonce = flumm.nonce;
            flumm.nonce++;


            bytes32 claimId = getClaimId(
                flumm.flummId,
                to,
                adjustedAmount,
                minAmountOut,
                totalSent,
                nonce,
                attestedCheckpoint
            );

            checkpointId = flumm.checkpoints.push(claimId, totalSent);

            emit TransferSent(
                flumm.flummId,
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
        flumm.dispatcher.dispatchMessage{value: msg.value}(flumm.counterpartChainId, address(this), confirmCheckpointData);

        // Collect tokens
        IERC20(flumm.token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function postClaim(
        FLUMM storage flumm,
        bytes32 claimId,
        bytes32 checkpointId,
        uint256 totalSent
    )
        internal
        returns (bool)
    {
        flumm.claimPostedAt[claimId] = block.timestamp;
        bytes32 calculatedCheckpointId = flumm.claims.push(claimId, totalSent);

        require(checkpointId == calculatedCheckpointId, "FLUMMLib: invalid checkpoint");
    }

    function removeClaim(
        FLUMM storage flumm,
        bytes32 checkpointId,
        uint256 nonce
    )
        internal
    {
        flumm.claims.pop(nonce, checkpointId);
    }

    function bond(
        FLUMM storage flumm,
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
        // uint256 stakeBalance = flumm.stakingRegistry.getStakedBalance("Bonder", msg.sender);
        // require(stakeBalance >= minBonderStake, "FLUMMLib: insufficient stake");

        if (attestedCheckpoint != bytes32(0)) {
            require(flumm.checkpoints.isCheckpoint(attestedCheckpoint), "FLUMMLib: attested checkpoint mismatch");
        }

        bytes32 claimId = getClaimId(
            flumm.flummId,
            to,
            amount,
            minAmountOut,
            totalSent,
            nonce,
            attestedCheckpoint
        );

        uint256 bonus = flumm.calcBonus(amount, totalSent, flumm.checkpoints.getTotalSent());
        uint256 adjustedAmount = amount + bonus;

        flumm.postClaim(claimId, checkpointId, totalSent);

        uint256 balance = flumm.balance[msg.sender] + adjustedAmount;
        flumm.balance[msg.sender] = balance;
        flumm.withdrawable[msg.sender].set(block.timestamp, balance);
        flumm.minTotalSent[msg.sender].set(block.timestamp, totalSent);

        IERC20(flumm.token).transferFrom(msg.sender, to, adjustedAmount);

        emit TransferBonded(
            claimId,
            flumm.flummId,
            to,
            amount,
            minAmountOut,
            totalSent
        );
    }

    function withdraw(FLUMM storage flumm, uint256 amount, uint256 time) internal {
        uint256 withdrawable = flumm.getWithdrawableBalance(msg.sender, time);
        require(withdrawable >= amount, "FLUMMLib: insufficient withdrawable balance");

        flumm.withdrawn[msg.sender] += amount;
        IERC20(flumm.token).safeTransfer(msg.sender, amount);
    }

    function withdrawAll(FLUMM storage flumm, uint256 time) internal {
        uint256 amount = flumm.getWithdrawableBalance(msg.sender, time);

        flumm.withdrawn[msg.sender] += amount;
        IERC20(flumm.token).safeTransfer(msg.sender, amount);
    }

    // on deposit
    function calcFee(FLUMM storage flumm, uint256 amount, uint256 attestedTotalSent) internal view returns (uint256) {
        // if there is enough surplus for the claim, return 0 fee
        uint256 totalSent = flumm.checkpoints.totalSent();
        if (attestedTotalSent > totalSent + amount) return 0;

        uint256 startDeficit = attestedTotalSent - totalSent;
        uint256 endDeficit = 0;
        if (startDeficit > amount) {
            endDeficit = startDeficit - amount;
        }

        uint256 avgDeficit = (startDeficit + endDeficit) / 2;
        uint256 rate = avgDeficit * flumm.rateDelta / 10e18;
        uint256 fee = amount * rate / 10e18;

        return fee;
    }

    // on withdrawal
    function calcBonus(FLUMM storage flumm, uint256 amount, uint256 totalSent, uint256 attestedTotalSent) internal view returns (uint256) {
        // if liquidity was freed, calculate the bonus
        if (totalSent >= attestedTotalSent) return 0;

        uint256 endDeficit = attestedTotalSent - totalSent;
        uint256 startDeficit = 0;
        if (endDeficit > amount) {
            startDeficit = endDeficit - amount;
        }

        uint256 avgDeficit = (startDeficit + endDeficit) / 2;
        uint256 rate = avgDeficit * flumm.rateDelta / 10e18;
        uint256 bonus = amount * rate / 10e18;

        return bonus;
    }

    function getFLUMMId(uint256 chainId0, IERC20 token0, uint256 chainId1, IERC20 token1) internal view returns (bytes32) {
        bool isAssending = chainId0 < chainId1;

        uint256 chainIdA = isAssending ? chainId0 : chainId1;
        uint256 chainIdB = isAssending ? chainId1 : chainId0;
        IERC20 tokenA = isAssending ? token0 : token1;
        IERC20 tokenB = isAssending ? token1 : token0;

        return keccak256(abi.encodePacked(chainIdA, tokenA, chainIdB, tokenB));
    }

    function getHead(FLUMM storage flumm) internal view returns (bytes32) {
        uint256 chainLength = flumm.checkpoints.checkpoints.length;
        if (chainLength == 0) return bytes32(0);
        return flumm.checkpoints.getCheckpointData(chainLength - 1).checkpointId;
    }

    function getWithdrawableBalance(FLUMM storage flumm, address bonder, uint256 time) internal view returns (uint256) {
        uint256 minTotalSent = flumm.minTotalSent[bonder].get(time);
        uint256 withdrawable = flumm.withdrawable[bonder].get(time);
        require(minTotalSent != 0, "FLUMMLib: Invalid time");
        require(withdrawable != 0, "FLUMMLib: Invalid time");

        uint256 totalSent = flumm.checkpoints.totalSent();
        uint256 withdrawn = flumm.withdrawn[bonder];
        if (totalSent < minTotalSent || withdrawable < withdrawn) {
            return 0;
        } else {
            return withdrawable - withdrawn;
        }
    }

    function getClaimId(
        bytes32 flummId,
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
                flummId,
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

    function getFee(FLUMM storage flumm) internal view returns (uint256) {
        uint256[] memory chainIds = new uint256[](1);
        chainIds[0] = flumm.counterpartChainId;
        return ICrossChainFees(address(flumm.dispatcher)).getFee(chainIds);
    }
}