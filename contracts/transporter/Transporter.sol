//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ITransportLayer.sol";
import "./libraries/Error.sol";

abstract contract Transporter is Ownable, ITransportLayer {
    address public dispatcher;
    mapping(uint256 => mapping(bytes32 => bool)) public provenCommitments;
    uint256 public feeReserve;
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
        feeReserve += msg.value;
    }

    function setDispatcher(address _dispatcher) external {
        dispatcher = _dispatcher;
    }

    function isCommitmentProven(uint256 fromChainId, bytes32 commitment) external view returns (bool) {
        return provenCommitments[fromChainId][commitment];
    }

    function _setProvenCommitment(uint256 fromChainId, bytes32 commitment) internal {
        provenCommitments[fromChainId][commitment] = true;
        emit CommitmentProven(fromChainId, commitment);
    }

    /**
     * @notice getChainId can be overridden by subclasses if needed for compatibility or testing purposes.
     * @dev Get the current chainId
     * @return chainId The current chainId
     */
    function getChainId() public virtual view returns (uint256 chainId) {
        return block.chainid;
    }

    /**
     * @dev Distributes fees in excess of the `targetReserveSize` to the fee collector.
     */
    function distributeFees() external onlyFeeDistributor() {
        uint256 excessFees = feeReserve - targetReserveSize;
        emit ExcessFeesDistributed(feeRecipient, excessFees);
        (bool success, ) = feeRecipient.call{value: excessFees}("");
        if (!success) revert TransferFailed(feeRecipient, excessFees);
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setFeeDistributor(address _feeDistributor) external onlyOwner {
        feeDistributor = _feeDistributor;
    }

    function setTargetReserveSize(uint256 _targetReserveSize) external onlyOwner {
        targetReserveSize = _targetReserveSize;
    }
}
