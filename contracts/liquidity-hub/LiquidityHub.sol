//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SlidingWindowLib, SlidingWindow} from "./libraries/SlidingWindowLib.sol";
import {PathLib, Path} from "./libraries/PathLib.sol";
import {IMessageDispatcher} from "../ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../ERC5164/IMessageExecutor.sol";
// import {ICrossChainFees} from "../messenger/interfaces/ICrossChainFees.sol";
import {StakingRegistry} from "./StakingRegistry.sol";

import {console} from "forge-std/console.sol";

contract LiquidityHub is StakingRegistry {
    using SafeERC20 for IERC20;
    using PathLib for Path;

    mapping(bytes32 => Path) internal paths;

    event TransferSent(
        bytes32 indexed claimId,
        bytes32 indexed pathId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent
    );

    event TransferBonded(
        bytes32 indexed claimId,
        bytes32 indexed pathId,
        address indexed to,
        uint256 amount,
        uint256 minAmountOut,
        uint256 totalSent
    );

    function initPath(
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
        bytes32 pathId = PathLib.getPathId(block.chainid, token, counterpartChainId, counterpartToken);
        Path storage path = paths[pathId];
        path.initialize(
            pathId,
            token,
            counterpartChainId,
            counterpartToken,
            dispatcher,
            executor,
            StakingRegistry(address(this)),
            rateDelta
        );

        return pathId;
    }

    function send(
        bytes32 pathId,
        address to,
        uint256 amount,
        uint256 minAmountOut,
        bytes32 attestedCheckpoint
    )
        external
        payable
    {
        Path storage path = paths[pathId];
        path.send(to, amount, minAmountOut, attestedCheckpoint);
    }

    function postClaim(
        bytes32 pathId,
        bytes32 claimId,
        bytes32 head,
        uint256 totalSent
    )
        external
    {
        Path storage path = paths[pathId];
        path.postClaim(claimId, head, totalSent);
    }

    function removeClaim(
        bytes32 pathId,
        bytes32 checkpointId,
        uint256 nonce
    )
        external
    {
        Path storage path = paths[pathId];
        path.removeClaim(checkpointId, nonce);
    }

    function bond(
        bytes32 pathId,
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
        Path storage path = paths[pathId];
        path.bond(checkpointId, to, amount, minAmountOut, totalSent, nonce, attestedCheckpoint);
    }

    function withdraw(bytes32 pathId, uint256 amount, uint256 time) external {
        Path storage path = paths[pathId];
        path.withdraw(amount, time);
    }

    function withdrawAll(bytes32 pathId, uint256 time) external {
        Path storage path = paths[pathId];
        uint256 amount = path.getWithdrawableBalance(msg.sender, time);
        path.withdraw(amount, time);
    }

    function getWithdrawableBalance(bytes32 pathId, address recipient, uint256 time) external view returns (uint256) {
        Path storage path = paths[pathId];
        return path.getWithdrawableBalance(recipient, time);
    }

    function getPathId(uint256 chainId0, IERC20 token0, uint256 chainId1, IERC20 token1) external view returns (bytes32) {
        return PathLib.getPathId(chainId0, token0, chainId1, token1);
    }

    function getFee(bytes32 pathId) external view returns (uint256) {
        Path storage path = paths[pathId];
        return path.getFee();
    }

    function getPathInfo(bytes32 pathId) external view returns (uint256, IERC20, uint256, IERC20) {
        Path storage path = paths[pathId];
        return (block.chainid, path.token, path.counterpartChainId, path.counterpartToken);
    }
}
