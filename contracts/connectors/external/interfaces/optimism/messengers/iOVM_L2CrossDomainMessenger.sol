// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
// +build ovm
pragma solidity >0.5.0;
pragma experimental ABIEncoderV2;

/* Interface Imports */
import { iOVM_BaseCrossDomainMessenger } from "./iOVM_BaseCrossDomainMessenger.sol";

/**
 * @title iOVM_L2CrossDomainMessenger
 */
interface iOVM_L2CrossDomainMessenger is iOVM_BaseCrossDomainMessenger {}