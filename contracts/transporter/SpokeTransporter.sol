//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Transporter.sol";
import "./HubTransporter.sol";
import "../interfaces/ICrossChainFees.sol";

interface IHubBundleTransporterer {
    function receiveOrForwardCommitment(
        bytes32 commitment,
        uint256 commitmentFees,
        uint256 toChainId,
        uint256 commitTime
    ) external payable;
}

contract SpokeTransporter is Ownable, Transporter {
    /* events */
    event FeePaid(address indexed to, uint256 amount, uint256 feesCollected);

    /* constants */
    uint256 public immutable l1ChainId;

    /* config*/
    address public hubTransporterConnector;
    uint256 public pendingFeeBatchSize;

    /* state */
    mapping(uint256 => bytes32) public pendingBundleNonceForChainId;
    mapping(uint256 => bytes32[]) public pendingMessageIdsForChainId;
    mapping(bytes32 => uint256) public feeForCommitment;

    modifier onlyHub() {
        if (msg.sender != hubTransporterConnector) {
            revert InvalidSender(msg.sender);
        }
        _;
    }

    constructor(uint256 _l1ChainId, uint256 _pendingFeeBatchSize) {
        l1ChainId = _l1ChainId;
        pendingFeeBatchSize = _pendingFeeBatchSize;
    }

    /// @notice Dispatches a commitment from this spoke to another chain via the hub
    /// @param toChainId The destination chain ID for the commitment
    /// @param commitment The commitment hash to dispatch
    /// @dev The dispatcher sends all collected fees for the bundle to the transporter along with the `dispatchCommitment` call
    function dispatchCommitment(uint256 toChainId, bytes32 commitment) external payable onlyDispatcher {
        address _hubTransporterConnector = hubTransporterConnector;

        // Calculate required fee for cross-chain message to hub
        uint256 messageFee = ICrossChainFees(_hubTransporterConnector).getFee(toChainId);
        require(msg.value >= messageFee, "Insufficient fee");

        // The remaining fee is used to incentivize relayers on the hub chain
        uint256 fee = msg.value - messageFee;
        feeForCommitment[commitment] = fee;

        emit CommitmentDispatched(toChainId, commitment, block.timestamp);

        // Send commitment to hub
        // The hub will forward this commitment to its final destination if needed
        IHubBundleTransporterer(_hubTransporterConnector).receiveOrForwardCommitment{value: messageFee}(
            commitment,
            fee,
            toChainId,
            block.timestamp
        );
    }

    /// @notice Receives a commitment from the hub and marks it as proven
    /// @param fromChainId The chain ID where the commitment originated
    /// @param commitment The commitment hash being received
    function receiveCommitment(uint256 fromChainId, bytes32 commitment) external onlyHub {
        _setProvenCommitment(fromChainId, commitment);
    }

    /// @notice Pays the relayer for relaying the commitment on the hub chain
    /// @param relayer The address that relayed the bundle on the hub
    /// @param relayerFee The amount to pay the relayer
    /// @param commitment The commitment being relayed
    /// @dev This function is called by the HubTransporter after the call to `receiveOrForwardCommitment` has been relayed
    function payRelayerFee(address relayer, uint256 relayerFee, bytes32 commitment) external onlyHub {
        uint256 feeCollected = feeForCommitment[commitment];

        if (feeCollected > relayerFee) {
            // Excess fees go to the protocol reserve for future operations
            uint256 feeDifference = feeCollected - relayerFee;
            feeReserve += feeDifference;
        } else if (relayerFee > feeCollected) {
            // If relayer fee exceeds collected fees, use reserve to cover difference
            // This ensures relayers are always paid fairly even if fees were underestimated
            uint256 feeDifference = relayerFee - feeCollected;
            if (feeDifference > feeReserve) revert FeesExhausted();
            feeReserve -= feeDifference;
        }

        emit FeePaid(relayer, relayerFee, feeCollected);

        // Transfer the relayer fee
        (bool success, ) = relayer.call{value: relayerFee}("");
        if (!success) revert TransferFailed(relayer, relayerFee);
    }

    /* Setters */

    /// @notice Sets the hub connector address for communicating with the hub chain
    /// @param _hubTransporterConnector The address of the hub transporter connector
    function setHubConnector(address _hubTransporterConnector) public onlyOwner {
        if (_hubTransporterConnector == address(0)) revert NoZeroAddress();

        hubTransporterConnector = _hubTransporterConnector;
    }

    /// @notice Sets the pending fee batch size for batching operations
    /// @param _pendingFeeBatchSize The new batch size (0 will flush pending fees for every bundle)
    function setpendingFeeBatchSize(uint256 _pendingFeeBatchSize) external onlyOwner {
        pendingFeeBatchSize = _pendingFeeBatchSize;
    }
}
