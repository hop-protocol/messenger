//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

error NoZeroAddress();
error NoZeroChainId();
error NoZeroExitTime();
error NoZeroMessageFee();
error NoZeroMaxBundleMessages();
error NoZeroRelayWindow();
error NoZeroAbsoluteMaxFee();
error NoZeroMaxFeeBPS();
error BundleNotFound(bytes32 bundleRoot);
error InvalidProof(
    bytes32 bundleRoot,
    bytes32 messageId,
    uint256 treeIndex,
    bytes32[] siblings,
    uint256 totalLeaves
);
error IncorrectFee(uint256 requiredFee, uint256 msgValue);
error InvalidRoute(uint256 toChainId);
error InvalidSender(address msgSender);
error NotHubBridge(address msgSender);
error InvalidChainId(uint256 chainId);
error NotEnoughFees(uint256 requiredFees, uint256 actualFees);
error NotCrossDomainMessage();
error NoPendingBundle();
error MessageIsSpent(bytes32 bundleNonce, uint256 treeIndex, bytes32 messageId);
error CannotMessageAddress(address to);
error PoolNotFull(uint256 poolSize, uint256 fullPoolSize);
error NotHub(address msgSender);
error ProveBundleFailed(uint256 fromChainId, bytes32 bundleNonce);
error InvalidBundle(uint256 fromChainId, bytes32 bundleNonce, address to);
error FeesExhausted();
error TransferFailed(address relayer, uint256 relayerFee);
error InsufficientReserve(uint256 available, uint256 required);
error CommitmentAlreadyHasFee(bytes32 commitment);
error CommitmentAlreadyProven(uint256 fromChainId, bytes32 commitment);
