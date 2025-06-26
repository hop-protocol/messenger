//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Transporter.sol";
import "../interfaces/ICrossChainFees.sol";

interface ISpokeTransporter {
    function receiveCommitment(uint256 fromChainId, bytes32 commitment) external payable;
    function payRelayerFee(address relayer, uint256 relayerFee, bytes32 commitment) external;
}

contract HubTransporter is Transporter {
    /* events */
    event CommitmentRelayed(
        uint256 indexed fromChainId,
        uint256 toChainId,
        bytes32 indexed commitment,
        uint256 transportFee,
        uint256 relayWindowStart,
        address indexed relayer
    );

    event CommitmentForwarded(
        uint256 indexed fromChainId,
        uint256 indexed toChainId,
        bytes32 indexed commitment
    );

    /* constants */
    uint256 constant BASIS_POINTS = 10_000;

    /* config */
    mapping(address => uint256) private chainIdForSpokeConnector;
    mapping(uint256 => address) private spokeConnectorForChainId;
    mapping(uint256 => uint256) private exitTimeForChainId;
    uint256 public relayWindow;
    uint256 public absoluteMaxFee;
    uint256 public maxFeeBPS;

    constructor(
        uint256 _relayWindow,
        uint256 _absoluteMaxFee,
        uint256 _maxFeeBPS
    ) {
        if (_relayWindow == 0) revert NoZeroRelayWindow();
        if (_absoluteMaxFee == 0) revert NoZeroAbsoluteMaxFee();
        if (_maxFeeBPS == 0) revert NoZeroMaxFeeBPS();
        relayWindow = _relayWindow;
        absoluteMaxFee = _absoluteMaxFee;
        maxFeeBPS = _maxFeeBPS;
    }

    /// @notice Dispatches a commitment to a destination chain
    /// @dev This function is called by the dispatcher with all ETH collected for the bundle.
    /// If msg.value exceeds the required message fee, the excess ETH contributes to the fee reserve. Otherwise,
    /// the fee reserve is used to cover the difference.
    /// @param toChainId The destination chain ID
    /// @param commitment The commitment hash to dispatch
    function dispatchCommitment(uint256 toChainId, bytes32 commitment) external payable onlyDispatcher {        
        emit CommitmentDispatched(toChainId, commitment, block.timestamp);

        uint256 fromChainId = getChainId();
        address spokeConnector = getSpokeConnector(toChainId);
        uint256 messageFee = ICrossChainFees(spokeConnector).getFee(toChainId);

        // Forward commitment to spoke chain with exact message fee required
        ISpokeTransporter(spokeConnector).receiveCommitment{value: messageFee}(fromChainId, commitment); // Forward value for message fee
    }

    /// @notice Receives a commitment from a spoke chain and either processes it locally or forwards it to another spoke
    /// @param commitment The commitment hash being processed
    /// @param transportFee The fee collected for transporting this commitment
    /// @param toChainId The destination chain ID for the commitment
    /// @param commitTime The timestamp when the commitment was created
    function receiveOrForwardCommitment(
        bytes32 commitment,
        uint256 transportFee,
        uint256 toChainId,
        uint256 commitTime
    )
        external
        payable
    {
        // getSpokeChainId will revert for invalid msg.senders
        uint256 fromChainId = getSpokeChainId(msg.sender);

        // Route commitment to final destination
        if (toChainId == getChainId()) {
            // Destination is this hub chain - mark commitment as proven locally
            _setProvenCommitment(fromChainId, commitment);
        } else {
            // Destination is another spoke chain - forward through hub
            address toSpokeConnector = getSpokeConnector(toChainId);
            ISpokeTransporter toSpokeTransporter = ISpokeTransporter(toSpokeConnector);

            emit CommitmentForwarded(fromChainId, toChainId, commitment);

            // Pay the message fee from the fee reserve
            uint256 messageFee = ICrossChainFees(toSpokeConnector).getFee(toChainId);
            if (address(this).balance < messageFee) revert FeesExhausted();
            toSpokeTransporter.receiveCommitment{value: messageFee}(fromChainId, commitment);
        }

        emit CommitmentProven(
            fromChainId,
            commitment
        );

        uint256 relayWindowStart = commitTime + getSpokeExitTime(fromChainId);

        emit CommitmentRelayed(
            fromChainId,
            toChainId,
            commitment,
            transportFee,
            relayWindowStart,
            tx.origin
        );

        // Calculate and pay relay reward based on time elapsed
        // Rewards increase linearly during the relay window to incentivize timely relaying
        uint256 relayReward = getRelayReward(relayWindowStart, transportFee);
        address fromSpokeConnector = getSpokeConnector(fromChainId);

        // Instruct the source spoke chain to pay the relayer
        ISpokeTransporter(fromSpokeConnector).payRelayerFee(tx.origin, relayReward, commitment);
    }

    /* setters */

    /// @notice Sets the connector and configuration for a spoke chain
    /// @param chainId The chain ID of the spoke
    /// @param connector The address of the spoke connector contract
    /// @param exitTime The time delay for exiting from this spoke chain (determines start of relay window)
    function setSpokeConnector(
        uint256 chainId,
        address connector,
        uint256 exitTime
    )
        external
        onlyOwner
    {
        if (chainId == 0) revert NoZeroChainId();
        if (connector == address(0)) revert NoZeroAddress(); 
        if (exitTime == 0) revert NoZeroExitTime();

        chainIdForSpokeConnector[connector] = chainId;
        spokeConnectorForChainId[chainId] = connector;
        exitTimeForChainId[chainId] = exitTime;
    }

    /// @notice Sets the relay window duration for calculating relayer rewards
    /// @param _relayWindow The new relay window duration in seconds
    function setRelayWindow(uint256 _relayWindow) external onlyOwner {
        if (_relayWindow == 0) revert NoZeroRelayWindow();
        relayWindow = _relayWindow;
    }

    /// @notice Sets the absolute maximum fee that can be charged
    /// @param _absoluteMaxFee The new absolute maximum fee amount
    function setAbsoluteMaxFee(uint256 _absoluteMaxFee) external onlyOwner {
        absoluteMaxFee = _absoluteMaxFee;
    }

    /// @notice Sets the maximum fee as a percentage in basis points
    /// @param _maxFeeBPS The new maximum fee percentage (in basis points, where 10000 = 100%)
    function setMaxFeeBPS(uint256 _maxFeeBPS) external onlyOwner {
        maxFeeBPS = _maxFeeBPS;
    }

    /* getters */

    /// @notice Gets the connector address for a given spoke chain
    /// @param chainId The chain ID to get the connector for
    /// @return The address of the spoke connector
    function getSpokeConnector(uint256 chainId) public view returns (address) {
        address spoke = spokeConnectorForChainId[chainId];
        if (spoke == address(0)) revert InvalidRoute(chainId);
        return spoke;
    }

    /// @notice Gets the chain ID for a given connector address
    /// @param connector The connector address to get the chain ID for
    /// @return The chain ID associated with the connector
    function getSpokeChainId(address connector) public view returns (uint256) {
        uint256 chainId = chainIdForSpokeConnector[connector];
        if (chainId == 0) revert InvalidSender(connector);
        return chainId;
    }

    /// @notice Gets the exit time for a given spoke chain
    /// @param chainId The chain ID to get the exit time for
    /// @return The exit time in seconds for the spoke chain
    function getSpokeExitTime(uint256 chainId) public view returns (uint256) {
        uint256 exitTime = exitTimeForChainId[chainId];
        if (exitTime == 0) revert InvalidChainId(chainId);
        return exitTime;
    }

    /// @notice Calculates the relay reward based on timing and collected fees
    /// @param relayWindowStart The timestamp when the relay window started
    /// @param feesCollected The total fees collected for this commitment
    /// @return The calculated relay reward amount
    function getRelayReward(uint256 relayWindowStart, uint256 feesCollected) public view returns (uint256) {
        // No reward if relay window hasn't started (commitment is too recent)
        if (relayWindowStart >= block.timestamp) return 0;
        
        // Calculate time-based reward: longer delay = higher reward
        // This incentivizes relayers to process commitments quickly while allowing for reasonable delays
        uint256 relayReward = (block.timestamp - relayWindowStart) * feesCollected / relayWindow;
        
        // Apply both percentage-based and absolute maximum fee caps
        // This prevents excessive fees while allowing proportional rewards
        uint256 relativeMaxFee = feesCollected * maxFeeBPS / BASIS_POINTS;
        uint256 maxFee = Math.min(relativeMaxFee, absoluteMaxFee);
        return Math.min(relayReward, maxFee);
    }
}
