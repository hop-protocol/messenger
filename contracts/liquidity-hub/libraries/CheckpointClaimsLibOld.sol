//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SlidingWindowLib, SlidingWindow} from "./SlidingWindowLib.sol";
import {IMessageDispatcher} from "../../ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../../ERC5164/IMessageExecutor.sol";
import {ICrossChainFees} from "../../messenger/interfaces/ICrossChainFees.sol";

struct Checkpoint {
    bytes32 previousCheckpoint;
    bytes32 claimId;
    uint256 totalSent;
}

struct CheckpointChain {
    bytes32 head;
    mapping(bytes32 => Checkpoint) checkpoints;
    mapping(bytes32 => bytes32) fragments; // head -> tail
}

library CheckpointClaimsLib {
    function add(CheckpointChain storage chain, bytes32 head, bytes32 claimId, uint256 totalSent) internal {
        require(chain.head == head, "CheckpointChainLib: invalid head");
        bytes32 checkpoint = keccak256(abi.encodePacked(head, claimId, totalSent));
        chain.checkpoints[checkpoint] = Checkpoint(head, claimId, totalSent);
        chain.head = checkpoint;
    }

    function removeFragment(CheckpointChain storage chain, bytes32 fragmentTail) internal {
        bytes32 previousCheckpoint = chain.checkpoints[fragmentTail].previousCheckpoint;
        require(previousCheckpoint != bytes32(0), "CheckpointChainLib: invalid tail");

        chain.fragments[fragmentTail] = chain.head;
        chain.head = previousCheckpoint;
    }

    function reattatchFragment(CheckpointChain storage chain, bytes32 fragmentHead) internal {
        bytes32 fragmentTail = chain.fragments[fragmentHead];
        require(fragmentTail != bytes32(0), "CheckpointChainLib: fragement does not exist");
        Checkpoint memory fragmentTailCheckpoint = chain.checkpoints[fragmentTail];
        require(chain.head == fragmentTailCheckpoint.previousCheckpoint, "CheckpointChainLib: invalid tail");

        chain.head = fragmentHead;
    }
}
