//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "./shared-solidity/OverridableChainId.sol";
import "./libraries/Error.sol";
import "./libraries/MessengerLib.sol";
import "./libraries/MerkleTreeLib.sol";
import "./interfaces/ITransporter.sol";
import "./interfaces/ICrossChainFees.sol";

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

    /// @notice Creates a new Dispatcher contract
    /// @param _transporter Address of the transporter contract that handles cross-chain commitments
    constructor(address _transporter) EIP712("Dispatcher", "1") {
        if (_transporter == address(0)) revert NoZeroAddress();
        transporter = _transporter;
    }

    /// @notice Dispatches a message to be sent cross-chain, bundling it with other messages for efficiency
    /// @param toChainId The destination chain ID where the message should be executed
    /// @param to The target address on the destination chain
    /// @param data The calldata to execute on the target address
    /// @return messageId The unique identifier for the dispatched message
    function dispatchMessage(
        uint256 toChainId,
        address to,
        bytes calldata data
    )
        external
        payable
        returns (bytes32)
    {
        uint256 maxBundleMessages = maxBundleMessagesForChainId[toChainId];
        if (maxBundleMessages == 0) revert InvalidRoute(toChainId);

        // Validate exact fee payment to prevent overpayment
        {
            uint256 messageFee = messageFeeForChainId[toChainId];
            if (messageFee != msg.value) revert IncorrectFee(messageFee, msg.value);
        }

        uint256 fromChainId = getChainId();
        bytes32[] storage pendingMessageIds = pendingMessageIdsForChainId[toChainId];
        uint256 treeIndex = pendingMessageIds.length;

        bytes32 pendingBundleNonce = pendingBundleNonceForChainId[toChainId];
        
        // Generate unique messageId
        bytes32 messageId = MessengerLib.getMessageId(
            pendingBundleNonce,
            treeIndex,
            fromChainId,
            msg.sender,
            toChainId,
            to,
            data
        );

        // Add message to pending bundle and accumulate fees
        pendingMessageIds.push(messageId);
        pendingFeesForChainId[toChainId] += msg.value;

        emit MessageSent(messageId, msg.sender, toChainId, to, data);
        emit MessageBundled(pendingBundleNonce, treeIndex, messageId);

        // Auto-commit bundle when it reaches maximum capacity
        // This ensures bundles are transported efficiently without manual intervention
        if (pendingMessageIds.length >= maxBundleMessages) {
            _commitPendingBundle(toChainId);
        }

        return messageId;
    }

    /// @notice Commit a pending bundle to the transport layer before it is full
    /// @dev The caller must pay the remaining fees for the bundle
    /// @param toChainId The chain ID of the destination chain
    function commitPendingBundle(uint256 toChainId) external payable {
        if (pendingMessageIdsForChainId[toChainId].length == 0) revert NoPendingBundle();

        // Caller must pay the remaining fees for the bundle
        pendingFeesForChainId[toChainId] += msg.value;

        // Ensure there are enough fees to transport a full bundle
        // This prevents partial bundles from being stuck due to insufficient fees
        uint256 numMessages = maxBundleMessagesForChainId[toChainId];
        uint256 messageFee = messageFeeForChainId[toChainId];

        uint256 fullBundleFee = messageFee * numMessages;
        if (fullBundleFee != pendingFeesForChainId[toChainId]) revert NotEnoughFees(fullBundleFee, pendingFeesForChainId[toChainId]);

        _commitPendingBundle(toChainId);
    }

    function _commitPendingBundle(uint256 toChainId) private {
        bytes32[] storage pendingMessageIds = pendingMessageIdsForChainId[toChainId];
        if (pendingMessageIds.length == 0) {
            return;
        }

        bytes32 bundleNonce = pendingBundleNonceForChainId[toChainId];

        // Create merkle root of all messages in the bundle
        // This single hash represents proof of all messages in the bundle and will be transported cross-chain by the transporter
        bytes32 bundleRoot = MerkleTreeLib.getMerkleRoot(pendingMessageIds);
        uint256 bundleFees = pendingFeesForChainId[toChainId];

        // New pending bundle
        pendingBundleNonceForChainId[toChainId] = bytes32(uint256(pendingBundleNonceForChainId[toChainId]) + 1);

        // Setting the array length to 0 while leaving storage slots dirty saves gas 15k gas per
        // message. and is safe in this case because the array length is never set to a non-zero
        // number. This ensures dirty array slots can never be accessed until they're rewritten by
        // a `push()`.
        assembly {
            sstore(pendingMessageIds.slot, 0)
        }
        pendingFeesForChainId[toChainId] = 0;

        emit BundleCommitted(bundleNonce, bundleRoot, bundleFees, toChainId, block.timestamp);

        // Generate unique bundle identifier and dispatch to transport layer
        uint256 fromChainId = getChainId();
        bytes32 bundleId = getBundleId(fromChainId, toChainId, bundleNonce, bundleRoot);
        ITransporter(transporter).dispatchCommitment{value: bundleFees}(toChainId, bundleId);
    }

    /// @notice Sets or updates the routing configuration for a destination chain
    /// @param chainId The destination chain ID to configure
    /// @param messageFee The fee required per message for this route
    /// @param maxBundleMessages The maximum number of messages per bundle for this route
    function setRoute(uint256 chainId, uint256 messageFee, uint256 maxBundleMessages) public onlyOwner {
        if (chainId == 0) revert NoZeroChainId();
        if (messageFee == 0) revert NoZeroMessageFee();
        if (maxBundleMessages == 0) revert NoZeroMaxBundleMessages();

        // Initialize bundle nonce for new routes using domain separator
        // This ensures bundle nonces are unique across different chains and deployments
        if (pendingBundleNonceForChainId[chainId] == 0) {
            pendingBundleNonceForChainId[chainId] = initialBundleNonce(chainId);
        }

        messageFeeForChainId[chainId] = messageFee;
        maxBundleMessagesForChainId[chainId] = maxBundleMessages;
    }

    /* Getters */
    /// @notice Generates the initial bundle nonce for a destination chain using the domain separator
    /// @param toChainId The destination chain ID
    /// @return The initial bundle nonce for the chain
    function initialBundleNonce(uint256 toChainId) public view returns (bytes32) {
        return keccak256(abi.encodePacked(_domainSeparatorV4(), toChainId));
    }

    /// @notice Generates a unique bundle identifier from bundle parameters
    /// @param fromChainId The source chain ID
    /// @param toChainId The destination chain ID
    /// @param bundleNonce The bundle nonce
    /// @param bundleRoot The merkle root of all messages in the bundle
    /// @return The unique bundle identifier
    function getBundleId(uint256 fromChainId, uint256 toChainId, bytes32 bundleNonce, bytes32 bundleRoot) public pure returns (bytes32) {
        return keccak256(abi.encode(fromChainId, toChainId, bundleNonce, bundleRoot));
    }

    /// @notice Returns the message fee for sending to a specific chain
    /// @param chainId The destination chain ID
    /// @return fee The fee required per message for the specified chain
    function getFee(uint256 chainId) external override view returns (uint256 fee) {
        uint256 thisChainId = getChainId();
        if (chainId == thisChainId) revert InvalidChainId(chainId);
        return messageFeeForChainId[chainId];
    }
}
