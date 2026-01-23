// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ITransporter.sol";
import "../libraries/Error.sol";

/// @title Transporter
/// @notice Base contract for transporting cross-chain commitments
/// @dev Abstract contract that provides common functionality for Hub and Spoke transporters
/// Handles fee management, commitment tracking, and cross-chain message validation
abstract contract Transporter is Ownable, ITransporter {
    address public dispatcher;
    mapping(uint256 => mapping(bytes32 => bool)) public provenCommitments;
    uint256 public targetReserveSize;
    address public feeRecipient;
    address public feeDistributor;

    event ExcessFeesDistributed(address indexed to, uint256 amount);

    modifier onlyDispatcher() {
        if (msg.sender != dispatcher) revert InvalidSender(msg.sender);
        _;
    }

    modifier onlyFeeDistributor() {
        if (msg.sender != feeDistributor) revert InvalidSender(msg.sender);
        _;
    }

    receive() external payable {
        // contributes to fee reserve
    }

    /// @notice Sets the dispatcher address that can dispatch commitments
    /// @param _dispatcher The address of the dispatcher contract
    function setDispatcher(address _dispatcher) external onlyOwner {
        dispatcher = _dispatcher;
    }

    /// @notice Checks if a commitment has been proven for a given chain
    /// @param fromChainId The chain ID where the commitment originated
    /// @param commitment The commitment hash to check
    /// @return Whether the commitment has been proven
    function isCommitmentProven(uint256 fromChainId, bytes32 commitment) external view returns (bool) {
        return provenCommitments[fromChainId][commitment];
    }

    function _setProvenCommitment(uint256 fromChainId, bytes32 commitment) internal {
        if (provenCommitments[fromChainId][commitment]) revert CommitmentAlreadyProven(fromChainId, commitment);
        provenCommitments[fromChainId][commitment] = true;
        emit CommitmentProven(fromChainId, commitment);
    }

    /// @notice Gets the current chain ID
    /// @dev Can be overridden by subclasses if needed for compatibility or testing purposes
    /// @return chainId The current chain ID
    function getChainId() public virtual view returns (uint256 chainId) {
        return block.chainid;
    }

    /// @notice Distributes fees in excess of the target reserve size to the fee recipient
    /// @dev Calculates excess fees above the target reserve size and transfers them
    function distributeFees() external onlyFeeDistributor() {
        uint256 feeReserve = address(this).balance;
        if (address(this).balance < targetReserveSize) revert InsufficientReserve(feeReserve, targetReserveSize);
        // Calculate excess fees above the target reserve size
        // This ensures the protocol maintains a healthy reserve while distributing surplus
        uint256 excessFees = feeReserve - targetReserveSize;
        emit ExcessFeesDistributed(feeRecipient, excessFees);

        // Transfer excess fees to the designated recipient
        (bool success, ) = feeRecipient.call{value: excessFees}("");
        if (!success) revert TransferFailed(feeRecipient, excessFees);
    }

    /// @notice Sets the address that will receive distributed fees
    /// @param _feeRecipient The address to receive fees
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        if (_feeRecipient == address(0)) revert NoZeroAddress();
        feeRecipient = _feeRecipient;
    }

    /// @notice Sets the address authorized to distribute fees
    /// @param _feeDistributor The address authorized to call distributeFees
    function setFeeDistributor(address _feeDistributor) external onlyOwner {
        if (_feeDistributor == address(0)) revert NoZeroAddress();
        feeDistributor = _feeDistributor;
    }

    /// @notice Sets the target reserve size for fee management
    /// @param _targetReserveSize The target amount to keep in reserve
    function setTargetReserveSize(uint256 _targetReserveSize) external onlyOwner {
        targetReserveSize = _targetReserveSize;
    }
}
