// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

import "./Transporter.sol";
import "../interfaces/ICrossChainFees.sol";

interface IHubTransporter {
    function receiveOrForwardCommitment(
        bytes32 commitment,
        uint256 commitmentFees,
        uint256 toChainId,
        uint256 commitTime
    ) external payable;
}

contract SpokeTransporter is Transporter {
    /* events */
    event FeePaid(address indexed to, uint256 amount, uint256 feesCollected);

    /* constants */
    uint256 public immutable l1ChainId;

    /* config*/
    address public hubTransporterConnector;

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

    constructor(uint256 _l1ChainId) {
        if (_l1ChainId == 0) revert NoZeroChainId();
        l1ChainId = _l1ChainId;
    }

    /// @notice Dispatches a commitment from this spoke to another chain via the hub
    /// @param toChainId The destination chain ID for the commitment
    /// @param commitment The commitment hash to dispatch
    /// @dev The dispatcher sends all collected fees for the bundle to the transporter along with the `dispatchCommitment` call
    function dispatchCommitment(uint256 toChainId, bytes32 commitment) external payable onlyDispatcher {
        address _hubTransporterConnector = hubTransporterConnector;

        // Calculate required fee for cross-chain message to hub
        uint256 messageFee = ICrossChainFees(_hubTransporterConnector).getFee(toChainId);
        if (msg.value < messageFee) revert IncorrectFee(messageFee, msg.value);

        // The remaining fee is used to incentivize relayers on the hub chain
        uint256 fee = msg.value - messageFee;
        // Extra check to make sure a fee isn't overwritten
        if (feeForCommitment[commitment] > 0) revert CommitmentAlreadyHasFee(commitment);
        feeForCommitment[commitment] = fee;

        emit CommitmentDispatched(toChainId, commitment, block.timestamp);

        // Send commitment to hub
        // The hub will forward this commitment to its final destination if needed
        IHubTransporter(_hubTransporterConnector).receiveOrForwardCommitment{value: messageFee}(
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

        if (address(this).balance < relayerFee) revert FeesExhausted();

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
}
