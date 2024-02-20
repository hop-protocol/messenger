//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SlidingWindowLib, SlidingWindow} from "./SlidingWindowLib.sol";
import {IMessageDispatcher} from "../../ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../../ERC5164/IMessageExecutor.sol";
import {ICrossChainFees} from "../../messenger/interfaces/ICrossChainFees.sol";

struct CheckpointChain {
    Checkpoint[] checkpoints;
    mapping(bytes32 => uint256) indexForCheckpoint;
}

struct Checkpoint {
    bytes32 checkpointId;
    uint256 totalSent;
}

library CheckpointLib {
    function push(
        CheckpointChain storage chain,
        bytes32 claimId,
        uint256 totalSent
    )
        internal
        returns (bytes32 checkpointId)
    {
        Checkpoint[] storage checkpoints = chain.checkpoints;
        bytes32 previousHash = bytes32(0);
        uint256 length = checkpoints.length;
        if (length != 0) {
            previousHash = checkpoints[length - 1].checkpointId;
        }

        checkpointId = getHash(previousHash, claimId, totalSent);
        if (chain.indexForCheckpoint[checkpointId] == 0) {
            chain.indexForCheckpoint[checkpointId] = length;
            checkpoints.push(Checkpoint(checkpointId, totalSent));
        }
    }

    // function pushClaim(
    //     Checkpoint[] storage checkpoints,
    //     bytes32 claimId,
    //     uint256 totalSent,
    //     bytes32 head
    // )
    //     internal
    //     returns (bytes32 checkpointId)
    // {

    //     bytes32 previousHash = bytes32(0);
    //     if (checkpoints.length == 0) {
    //         require(head == bytes32(0), "CheckpointChainLib: invalid head");
    //     } else {
    //         previousHash = checkpoints[checkpoints.length - 1].checkpointId;
    //         require(previousHash == head, "CheckpointChainLib: invalid head");
    //     }

    //     checkpointId = getHash(previousHash, claimId, totalSent);
    //     checkpoints.push(Checkpoint(checkpointId, totalSent));
    // }

    function pop(CheckpointChain storage chain, uint256 nonce, bytes32 checkpointId) internal {
        require(checkpointId != bytes32(0), "LiquidityHub: checkpointId cannot be 0");
        Checkpoint[] storage checkpoints = chain.checkpoints;
        require(nonce < checkpoints.length, "LiquidityHub: invalid nonce");
        require(checkpoints[nonce].checkpointId == checkpointId, "LiquidityHub: invalid checkpointId");

        if (checkpoints.length > nonce) {
            checkpoints.pop();
        }
    }

    function popHead(CheckpointChain storage chain, bytes32 head) internal {
        Checkpoint[] storage checkpoints = chain.checkpoints;
        uint256 chainLength = checkpoints.length;
        require(checkpoints.length > 0, "CheckpointChainLib: empty chain");
        require(checkpoints[chainLength - 1].checkpointId == head, "CheckpointChainLib: invalid head");
        checkpoints.pop();
    }

    function getCheckpointData(CheckpointChain storage chain, bytes32 checkpoint) internal view returns (Checkpoint storage) {
        uint256 index = chain.indexForCheckpoint[checkpoint];
        return chain.checkpoints[index];
    }

    function getCheckpointData(CheckpointChain storage chain, uint256 index) internal view returns (Checkpoint storage) {
        return chain.checkpoints[index];
    }

    function getTotalSent(CheckpointChain storage chain) internal view returns (uint256) {
        Checkpoint[] storage checkpoints = chain.checkpoints;
        uint256 chainLength = checkpoints.length;
        if (chainLength == 0) return 0;
        return checkpoints[chainLength - 1].totalSent;
    }

    function getHash(
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

    function isCheckpoint(
        CheckpointChain storage chain,
        bytes32 checkpointId
    )
        internal
        view
        returns (bool)
    {
        // ToDo: Simplify
        uint256 index = chain.indexForCheckpoint[checkpointId];
        if (index >= chain.checkpoints.length) return false;
        return chain.checkpoints[index].checkpointId == checkpointId;
    }

    function totalSent(CheckpointChain storage chain) internal view returns (uint256) {
        Checkpoint[] storage checkpoints = chain.checkpoints;
        uint256 chainLength = checkpoints.length;
        if (chainLength == 0) return 0;
        uint256 totalSent = checkpoints[chainLength - 1].totalSent;
        return totalSent;
    }
}
