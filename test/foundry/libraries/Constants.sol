// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.19;

uint256 constant L1_CHAIN_ID = 11155111;
uint256 constant HUB_CHAIN_ID = 42069;
uint256 constant SPOKE_CHAIN_ID_0 = 11155420;
uint256 constant SPOKE_CHAIN_ID_1 = 84532;

address constant TREASURY = 0x1111000000000000000000000000000000001111;
address constant PUBLIC_GOODS = 0x2222000000000000000000000000000000002222;
address constant ARBITRARY_EOA = 0x3333000000000000000000000000000000003333;
uint256 constant MIN_PUBLIC_GOODS_BPS = 100_000;

// Fee distribution
uint256 constant FULL_POOL_SIZE = 100_000_000_000_000_000; // 0.1
uint256 constant MAX_TRANSPORT_FEE_ABSOLUTE = 50_000_000_000_000_000; // 0.05
uint256 constant MAX_TRANSPORT_FEE_BPS = 30_000; // 300%
uint256 constant EXIT_TIME = 60; // 1 min for testnet

// Fee collection
uint256 constant MAX_BUNDLE_MESSAGES = 1024;
uint256 constant MESSAGE_FEE = 7_000_000_000_000;
uint256 constant TRANSPORT_FEE = 7_000_000_000_000_000; // 0.007
uint256 constant RELAY_WINDOW = 12 * 3600; // 12 hours
uint256 constant BONDER_FEE_BPS = 0;
uint256 constant DEFAULT_TOKEN_FEE = 1 * 1e14; // 1 bps
uint256 constant SEND_FEE_GAS = 140_000;
uint256 constant UPDATE_FEE_GAS = 70_000;

// Message
uint256 constant DEFAULT_RESULT = 1234;
bytes32 constant DEFAULT_COMMITMENT = 0x1234500000000000000000000000000000000000000000000000000000012345;
uint256 constant DEFAULT_FROM_CHAIN_ID = SPOKE_CHAIN_ID_0;
uint256 constant DEFAULT_TO_CHAIN_ID = L1_CHAIN_ID;

// Penalties
uint256 constant INVALID_CLAIM_PENALTY = 50_000 * 1e18;

// General
uint256 constant ONE_WEEK = 604800;
uint256 constant BPS = 10_000;
uint256 constant ONE_TKN = 1e18;
uint256 constant SLOT_SIZE = 1 hours;
