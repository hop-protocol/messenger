//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

interface ILiquidityHub {
    function confirmCheckpoint(bytes32 checkpoint) external;
}
