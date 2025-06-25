// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@hop-protocol/erc5164/contracts/MessageExecutor.sol";
import "./shared-solidity/OverridableChainId.sol";
import "./interfaces/ITransporter.sol";
import "./libraries/Error.sol";
import "./libraries/Bitmap.sol";
import "./libraries/MerkleTreeLib.sol";
import "./libraries/MessengerLib.sol";

struct BundleProof {
    bytes32 bundleNonce;
    uint256 treeIndex;
    bytes32[] siblings;
    uint256 totalLeaves;
}

contract Executor is MessageExecutor, OverridableChainId {
    using BitmapLibrary for Bitmap;

    ITransporter public immutable transporter;
    // fromChainId -> bundleId -> verified status
    mapping(uint256 => mapping(bytes32 => bool)) public verifiedBundleIds;
    address public verificationManager;
    mapping(bytes32 => Bitmap) private spentMessagesForBundleNonce;

    event BundleProven(
        uint256 indexed fromChainId,
        bytes32 indexed bundleNonce,
        bytes32 bundleRoot,
        bytes32 bundleId
    );

    /// @notice Creates a new Executor contract
    /// @param _transporter Address of the transporter contract that handles cross-chain commitments
    constructor(address _transporter) {
        transporter = ITransporter(_transporter);
    }

    /// @notice Executes a cross-chain message after verifying its authenticity and bundle proof
    /// @param fromChainId The chain ID where the message originated
    /// @param from The address that sent the message on the source chain
    /// @param to The target address to receive the message on this chain
    /// @param data The calldata to execute on the target address
    /// @param bundleProof Merkle proof data proving the message was included in a verified bundle
    function executeMessage(
        uint256 fromChainId,
        address from,
        address to,
        bytes calldata data,
        BundleProof memory bundleProof
    ) external {
        // Reconstruct the messageId using the same parameters used during dispatch
        // This ensures the message being executed matches what was originally sent
        bytes32 messageId = MessengerLib.getMessageId(
            bundleProof.bundleNonce,
            bundleProof.treeIndex,
            fromChainId,
            from,
            getChainId(),
            to,
            data
        );
        
        // Validate the merkle proof to ensure this message was included in the bundle
        // This cryptographically proves the message is authentic and was part of the original bundle
        bytes32 bundleRoot = MerkleTreeLib.processProof(
            messageId,
            bundleProof.treeIndex,
            bundleProof.siblings,
            bundleProof.totalLeaves
        );

        // Verify the bundle has been proven valid by the transport layer
        bool _isBundleVerified = isBundleVerified(
            fromChainId,
            bundleProof.bundleNonce,
            bundleRoot
        );
        if (!_isBundleVerified) {
            revert InvalidBundle(verificationManager, fromChainId, bundleProof.bundleNonce, to);
        }

        // Prevent double-spending by marking this message as used
        // Uses a bitmap for gas-efficient storage of spent message indices
        Bitmap storage spentMessages = spentMessagesForBundleNonce[bundleProof.bundleNonce];
        spentMessages.switchTrue(bundleProof.treeIndex); // Reverts if already true

        // Execute the cross-chain message call
        _execute(messageId, fromChainId, from, to, data);
    }

    /// @notice Checks if a message at a specific index has already been executed for a given bundle
    /// @param bundleNonce The nonce of the bundle to check
    /// @param index The tree index of the message within the bundle
    /// @return True if the message has been spent, false otherwise
    function isMessageSpent(bytes32 bundleNonce, uint256 index) public view returns (bool) {
        Bitmap storage spentMessages = spentMessagesForBundleNonce[bundleNonce];
        return spentMessages.isTrue(index);
    }

    /// @notice Proves that a bundle has been committed on the source chain and caches the verification
    /// @param fromChainId The chain ID where the bundle was committed
    /// @param bundleNonce The nonce of the bundle to prove
    /// @param bundleRoot The merkle root of all messages in the bundle
    function proveBundle(uint256 fromChainId, bytes32 bundleNonce, bytes32 bundleRoot) external {
        // Generate the unique bundle identifier used by the transport layer
        bytes32 bundleId = MessengerLib.getBundleId(fromChainId, getChainId(), bundleNonce, bundleRoot);
        
        // Check with the transporter that this bundle commitment has been proven
        // The transporter validates that the bundle was properly committed on the source chain
        bool verified = transporter.isCommitmentProven(fromChainId, bundleId);
        if (!verified) revert ProveBundleFailed(fromChainId, bundleNonce);

        // Cache the verification result to avoid repeated transporter calls
        verifiedBundleIds[fromChainId][bundleId] = true;
        emit BundleProven(fromChainId, bundleNonce, bundleRoot, bundleId);
    }

    /// @notice Checks if a bundle has been verified and cached locally
    /// @param fromChainId The chain ID where the bundle was committed
    /// @param bundleNonce The nonce of the bundle to check
    /// @param bundleRoot The merkle root of all messages in the bundle
    /// @return True if the bundle has been verified, false otherwise
    function isBundleVerified(
        uint256 fromChainId,
        bytes32 bundleNonce,
        bytes32 bundleRoot
    )
        public
        view
        returns (bool)
    {
        // Generate bundle ID and check if it's been verified and cached locally
        bytes32 bundleId = MessengerLib.getBundleId(fromChainId, getChainId(), bundleNonce, bundleRoot);
        return verifiedBundleIds[fromChainId][bundleId];
    }
}