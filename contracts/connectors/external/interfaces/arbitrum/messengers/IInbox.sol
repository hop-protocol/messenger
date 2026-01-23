// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/nitro/blob/master/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.2;

import "./IBridge.sol";

interface IInbox {
    function sendL2Message(bytes calldata messageData) external returns (uint256);
    function bridge() external view returns (IBridge);
    function unsafeCreateRetryableTicket(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes calldata data
    ) external payable returns (uint256);
    function calculateRetryableSubmissionFee(uint256 dataLength, uint256 baseFee) external returns (uint256);
}