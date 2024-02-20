//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SlidingWindowLib, SlidingWindow} from "./libraries/SlidingWindowLib.sol";
import {FLUMMLib, FLUMM} from "./libraries/FLUMMLib.sol";
import {IMessageDispatcher} from "../ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../ERC5164/IMessageExecutor.sol";
// import {ICrossChainFees} from "../messenger/interfaces/ICrossChainFees.sol";
import {StakingRegistry} from "./StakingRegistry.sol";

import {console} from "forge-std/console.sol";

contract LiquidityHub is StakingRegistry {
    using SafeERC20 for IERC20;
    using FLUMMLib for FLUMM;

    mapping(bytes32 => FLUMM) internal flumms;

    event TransferSent(
        bytes32 indexed claimId,
        bytes32 indexed flummId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent
    );

    event TransferBonded(
        bytes32 indexed claimId,
        bytes32 indexed flummId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent
    );

    function initFLUMM(
        IERC20 token,
        uint256 counterpartChainId,
        IERC20 counterpartToken,
        IMessageDispatcher dispatcher,
        IMessageExecutor executor,
        uint256 rateDelta
    )
        public
        returns
        (bytes32)
    {
        bytes32 flummId = FLUMMLib.getFLUMMId(block.chainid, token, counterpartChainId, counterpartToken);
        FLUMM storage flumm = flumms[flummId];
        flumm.initialize(
            flummId,
            token,
            counterpartChainId,
            counterpartToken,
            dispatcher,
            executor,
            StakingRegistry(address(this)),
            rateDelta
        );

        return flummId;
    }

    function send(
        bytes32 flummId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        bytes32 attestedCheckpoint
    )
        external
        payable
    {
        FLUMM storage flumm = flumms[flummId];
        flumm.send(to, amount, minAmountOut, attestedCheckpoint);
    }

    function postClaim(
        bytes32 flummId,
        bytes32 claimId,
        bytes32 head,
        uint256 totalSent
    )
        external
    {
        FLUMM storage flumm = flumms[flummId];
        flumm.postClaim(claimId, head, totalSent);
    }

    function removeClaim(
        bytes32 flummId,
        bytes32 checkpointId,
        uint256 nonce
    )
        external
    {
        FLUMM storage flumm = flumms[flummId];
        flumm.removeClaim(checkpointId, nonce);
    }

    function bond(
        bytes32 flummId,
        bytes32 checkpointId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent,
        uint256 nonce,
        bytes32 attestedCheckpoint
    )
        external
    {
        FLUMM storage flumm = flumms[flummId];
        flumm.bond(checkpointId, to, amount, minAmountOut, totalSent, nonce, attestedCheckpoint);
    }

    function withdraw(bytes32 flummId, uint256 amount) external {
        FLUMM storage flumm = flumms[flummId];
        flumm.withdraw(amount);
    }

    function getWithdrawableBalance(bytes32 flummId, address recipient, uint256 time) external view returns (uint256) {
        FLUMM storage flumm = flumms[flummId];
        return flumm.getWithdrawableBalance(recipient, time);
    }

    function withdrawClaims(bytes32 flummId, address recipient, uint256 window) external {
        // ToDo: set min window age
        // FLUMM storage flumm = flumms[flummId];
        // uint256 withdrawalAmount = flumm.getWithdrawableBalance(recipient, window);
        // flumm.balance[recipient] -= withdrawalAmount;
        // flumm.totalWithdrawn += withdrawalAmount;
        // IERC20(flumm.token).safeTransfer(recipient, withdrawalAmount);
    }

    function getFLUMMId(uint256 chainId0, IERC20 token0, uint256 chainId1, IERC20 token1) external view returns (bytes32) {
        return FLUMMLib.getFLUMMId(chainId0, token0, chainId1, token1);
    }

    function getFee(bytes32 flummId) external view returns (uint256) {
        FLUMM storage flumm = flumms[flummId];
        return flumm.getFee();
    }

    function getFLUMMInfo(bytes32 flummId) external view returns (uint256, IERC20, uint256, IERC20) {
        FLUMM storage flumm = flumms[flummId];
        return (block.chainid, flumm.token, flumm.counterpartChainId, flumm.counterpartToken);
    }
}
