//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Transporter.sol";
import "./HubTransporter.sol";
import "../interfaces/ICrossChainFees.sol";
import "hardhat/console.sol";

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

    function dispatchCommitment(uint256 toChainId, bytes32 commitment) external payable onlyDispatcher {
        address _hubTransporterConnector = hubTransporterConnector;

        uint256 messageFee = ICrossChainFees(_hubTransporterConnector).getFee(toChainId);
        require(msg.value >= messageFee, "Insufficient fee");

        uint256 fee = msg.value - messageFee;
        feeForCommitment[commitment] = fee;

        emit CommitmentDispatched(toChainId, commitment, block.timestamp);

        IHubBundleTransporterer(_hubTransporterConnector).receiveOrForwardCommitment{value: messageFee}(
            commitment,
            fee,
            toChainId,
            block.timestamp
        );
    }

    function receiveCommitment(uint256 fromChainId, bytes32 commitment) external onlyHub {
        _setProvenCommitment(fromChainId, commitment);
    }

    /**
     * @dev Pay the relayer for relaying the commitment on L1
     * @notice This function is called by the HubTransporter after the call to
     * `receiveOrForwardCommitment` has been relayed
     * @param relayer The address that relayed the bundle on L1
     * @param relayerFee The amount to pay the relayer
     * @param commitment The commitment being relayed
     */
    function payRelayerFee(address relayer, uint256 relayerFee, bytes32 commitment) external onlyHub {
        uint256 feeCollected = feeForCommitment[commitment];

        if (feeCollected > relayerFee) {
            uint256 feeDifference = feeCollected - relayerFee;
            feeReserve += feeDifference;
        } else if (relayerFee > feeCollected) {
            uint256 feeDifference = relayerFee - feeCollected;
            if (feeDifference > feeReserve) revert FeesExhausted();
            feeReserve -= feeDifference;
        }

        emit FeePaid(relayer, relayerFee, feeCollected);

        (bool success, ) = relayer.call{value: relayerFee}("");
        if (!success) revert TransferFailed(relayer, relayerFee);
    }

    /* Setters */

    function setHubConnector(address _hubTransporterConnector) public onlyOwner {
        if (_hubTransporterConnector == address(0)) revert NoZeroAddress();

        hubTransporterConnector = _hubTransporterConnector;
    }

    /// @notice `pendingFeeBatchSize` of 0 will flush the pending fees for every bundle.
    function setpendingFeeBatchSize(uint256 _pendingFeeBatchSize) external onlyOwner {
        pendingFeeBatchSize = _pendingFeeBatchSize;
    }
}
