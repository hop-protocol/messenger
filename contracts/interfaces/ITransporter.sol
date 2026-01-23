// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

interface ITransporter {
    /* events */
    event CommitmentDispatched(
        uint256 indexed toChainId,
        bytes32 indexed commitment,
        uint256 timestamp
    );

    event CommitmentProven(
        uint256 indexed fromChainId,
        bytes32 indexed commitment
    );

    function dispatchCommitment(uint256 toChainId, bytes32 commitment) external payable;
    function isCommitmentProven(uint256 fromChainId, bytes32 commitment) external returns (bool);
}
