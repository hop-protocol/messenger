//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "../../shared-solidity/OverridableChainId.sol";
import "../libraries/Error.sol";
import "../libraries/MessengerLib.sol";
import "../libraries/MerkleTreeLib.sol";
import "../interfaces/ITransportLayer.sol";
import "../interfaces/ICrossChainFees.sol";

struct Route {
    uint256 chainId;
    uint128 messageFee;
    uint128 maxBundleMessages;
}

struct RouteData {
    uint128 messageFee;
    uint128 maxBundleMessages;
}

contract Dispatcher is Ownable, EIP712, OverridableChainId, ICrossChainFees {
    using MerkleTreeLib for bytes32;

    /* events */
    event MessageSent(
        bytes32 indexed messageId,
        address indexed from,
        uint256 indexed toChainId,
        address to,
        bytes data
    );
    event MessageBundled(
        bytes32 indexed bundleNonce,
        uint256 indexed treeIndex,
        bytes32 indexed messageId
    );
    event BundleCommitted(
        bytes32 indexed bundleNonce,
        bytes32 bundleRoot,
        uint256 bundleFees,
        uint256 indexed toChainId,
        uint256 commitTime
    );

    /* config */
    address public transporter;
    mapping(uint256 => uint256) public messageFeeForChainId;
    mapping(uint256 => uint256) public maxBundleMessagesForChainId;

    /* state */
    mapping(uint256 => bytes32) public pendingBundleNonceForChainId;
    mapping(uint256 => bytes32[]) public pendingMessageIdsForChainId;
    mapping(uint256 => uint256) public pendingFeesForChainId;

    constructor(address _transporter) EIP712("Dispatcher", "1") {
        transporter = _transporter;
    }

    function dispatchMessage(
        uint256 toChainId,
        address to,
        bytes calldata data
    )
        external
        payable
        returns (bytes32)
    {
        // RouteData memory _routeData = routeData[toChainId];
        uint256 maxBundleMessages = maxBundleMessagesForChainId[toChainId];
        if (maxBundleMessages == 0) revert InvalidRoute(toChainId);

        {
            uint256 messageFee = messageFeeForChainId[toChainId];
            if (messageFee != msg.value) revert IncorrectFee(messageFee, msg.value);
        }

        uint256 fromChainId = getChainId();
        bytes32[] storage pendingMessageIds = pendingMessageIdsForChainId[toChainId];
        uint256 treeIndex = pendingMessageIds.length;

        bytes32 pendingBundleNonce = pendingBundleNonceForChainId[toChainId];
        bytes32 messageId = MessengerLib.getMessageId(
            pendingBundleNonce,
            treeIndex,
            fromChainId,
            msg.sender,
            toChainId,
            to,
            data
        );

        pendingMessageIds.push(messageId);
        pendingFeesForChainId[toChainId] += msg.value;

        emit MessageSent(messageId, msg.sender, toChainId, to, data);
        emit MessageBundled(pendingBundleNonce, treeIndex, messageId);

        if (pendingMessageIds.length >= maxBundleMessages) {
            _commitPendingBundle(toChainId);
        }

        return messageId;
    }

    function commitPendingBundle(uint256 toChainId) external payable {
        if (pendingMessageIdsForChainId[toChainId].length == 0) revert NoPendingBundle();

        pendingFeesForChainId[toChainId] += msg.value;

        uint256 numMessages = maxBundleMessagesForChainId[toChainId];
        uint256 messageFee = messageFeeForChainId[toChainId];

        uint256 fullBundleFee = messageFee * numMessages;
        if (fullBundleFee > pendingFeesForChainId[toChainId]) {
            revert NotEnoughFees(fullBundleFee, pendingFeesForChainId[toChainId]);
        }
        _commitPendingBundle(toChainId);
    }

    function _commitPendingBundle(uint256 toChainId) private {
        bytes32[] storage pendingMessageIds = pendingMessageIdsForChainId[toChainId];
        if (pendingMessageIds.length == 0) {
            return;
        }

        bytes32 bundleNonce = pendingBundleNonceForChainId[toChainId];
        bytes32 bundleRoot = MerkleTreeLib.getMerkleRoot(pendingMessageIds);
        uint256 bundleFees = pendingFeesForChainId[toChainId];

        // New pending bundle
        pendingBundleNonceForChainId[toChainId] = bytes32(uint256(pendingBundleNonceForChainId[toChainId]) + 1);

        // Setting the array length to 0 while leaving storage slots dirty saves gas 15k gas per
        // message. and is safe inthis case because the array length is never set to a non-zero
        // number. This ensures dirty array slots can never be accessed until they're rewritten by
        // a `push()`.
        assembly {
            sstore(pendingMessageIds.slot, 0)
        }
        pendingFeesForChainId[toChainId] = 0;

        emit BundleCommitted(bundleNonce, bundleRoot, bundleFees, toChainId, block.timestamp);

        uint256 fromChainId = getChainId();
        bytes32 bundleId = getBundleId(fromChainId, toChainId, bundleNonce, bundleRoot);
        ITransportLayer(transporter).dispatchCommitment{value: bundleFees}(toChainId, bundleId);
    }

    function setRoute(uint256 chainId, uint256 messageFee, uint256 maxBundleMessages) public onlyOwner {
        if (chainId == 0) revert NoZeroChainId();
        if (messageFee == 0) revert NoZeroMessageFee();
        if (maxBundleMessages == 0) revert NoZeroMaxBundleMessages();

        if (pendingBundleNonceForChainId[chainId] == 0) {
            pendingBundleNonceForChainId[chainId] = initialBundleNonce(chainId);
        }
        _commitPendingBundle(chainId);
        messageFeeForChainId[chainId] = messageFee;
        maxBundleMessagesForChainId[chainId] = maxBundleMessages;
    }

    /* Getters */
    function initialBundleNonce(uint256 toChainId) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_domainSeparatorV4(), toChainId));
    }

    function getBundleId(uint256 fromChainId, uint256 toChainId, bytes32 bundleNonce, bytes32 bundleRoot) public pure returns (bytes32) {
        return keccak256(abi.encode(fromChainId, toChainId, bundleNonce, bundleRoot));
    }

    function getFee(uint256[] calldata chainIds) external override view returns (uint256) {
        uint256 thisChainId = getChainId();
        uint256 fee = 0;
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            if (chainId != thisChainId) {
                fee += messageFeeForChainId[chainId];
            }
        }
        return fee;
    }
}
