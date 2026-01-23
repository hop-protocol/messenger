// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */

pragma solidity ^0.8.2;

interface IArbSys {
    function sendTxToL1(address destAddr, bytes calldata calldataForL1) external payable;
}
