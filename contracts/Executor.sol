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

    constructor(address _transporter) {
        transporter = ITransporter(_transporter);
    }

    function executeMessage(
        uint256 fromChainId,
        address from,
        address to,
        bytes calldata data,
        BundleProof memory bundleProof
    ) external {
        bytes32 messageId = MessengerLib.getMessageId(
            bundleProof.bundleNonce,
            bundleProof.treeIndex,
            fromChainId,
            from,
            getChainId(),
            to,
            data
        );
        bytes32 bundleRoot = MerkleTreeLib.processProof(
            messageId,
            bundleProof.treeIndex,
            bundleProof.siblings,
            bundleProof.totalLeaves
        );

        bool _isBundleVerified = isBundleVerified(
            fromChainId,
            bundleProof.bundleNonce,
            bundleRoot
        );
        if (!_isBundleVerified) {
            revert InvalidBundle(verificationManager, fromChainId, bundleProof.bundleNonce, to);
        }

        Bitmap storage spentMessages = spentMessagesForBundleNonce[bundleProof.bundleNonce];
        spentMessages.switchTrue(bundleProof.treeIndex); // Reverts if already true

        _execute(messageId, fromChainId, from, to, data);
    }

    function isMessageSpent(bytes32 bundleNonce, uint256 index) public view returns (bool) {
        Bitmap storage spentMessages = spentMessagesForBundleNonce[bundleNonce];
        return spentMessages.isTrue(index);
    }

    function proveBundle(uint256 fromChainId, bytes32 bundleNonce, bytes32 bundleRoot) external {
        bytes32 bundleId = MessengerLib.getBundleId(fromChainId, getChainId(), bundleNonce, bundleRoot);
        bool verified = transporter.isCommitmentProven(fromChainId, bundleId);
        if (!verified) revert ProveBundleFailed(fromChainId, bundleNonce);

        verifiedBundleIds[fromChainId][bundleId] = true;
        emit BundleProven(fromChainId, bundleNonce, bundleRoot, bundleId);
    }

    function isBundleVerified(
        uint256 fromChainId,
        bytes32 bundleNonce,
        bytes32 bundleRoot
    )
        public
        view
        returns (bool)
    {
        bytes32 bundleId = MessengerLib.getBundleId(fromChainId, getChainId(), bundleNonce, bundleRoot);
        return verifiedBundleIds[fromChainId][bundleId];
    }
}