// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

import "@hop-protocol/erc5164/contracts/IMessageExecutor.sol";
import "@hop-protocol/erc5164/contracts/MessageReceiver.sol";
import "../shared-solidity/ExecutorLib.sol";
import "../shared-solidity/Initializable.sol";

contract Alias is MessageReceiver, Initializable {
    using ExecutorLib for address;

    error InvalidCounterpart(address counterpart);
    error InvalidBridge(address msgSender);
    error InvalidFromChainId(uint256 fromChainId);

    address public baseExecutor;
    uint256 public sourceChainId;
    address public aliasDispatcher;

    event ETHReceived(address indexed sender, uint256 amount);

    /// @dev initialize to keep creation code consistent for create2 deployments
    function initialize(address _baseExecutor, uint256 _sourceChainId, address _aliasDispatcher) public initializer {
        require(_baseExecutor != address(0), "ALS: baseExecutor cannot be zero address");
        require(_aliasDispatcher != address(0), "ALS: aliasDispatcher cannot be zero address");
        require(_sourceChainId != 0, "ALS: sourceChainId cannot be zero");

        baseExecutor = _baseExecutor;
        aliasDispatcher = _aliasDispatcher;
        sourceChainId = _sourceChainId;
    }

    receive () external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function forwardMessage(
        address to,
        uint256 value,
        bytes calldata data
    )
        external
    {
        (, uint256 _fromChainId, address _from) = _crossChainContext();
        require(_fromChainId == sourceChainId, "ALS: Invalid _fromChainId");
        require(_from == aliasDispatcher, "ALS: Invalid _from");
        require(address(this).balance >= value, "ALS: Insufficient balance");

        to.execute(data, value);
    }
}
