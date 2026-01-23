// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */

pragma solidity ^0.8.2;

import "../shared-solidity/ExecutorLib.sol";
import "../shared-solidity/Initializable.sol";
import "../interfaces/ICrossChainFees.sol";

abstract contract Connector is Initializable, ICrossChainFees {
    using ExecutorLib for address;

    error InvalidCounterpart(address counterpart);
    error InvalidBridge(address msgSender);
    error InvalidFromChainId(uint256 fromChainId);

    address public target;
    address public counterpart;

    /// @dev initializer used to keep creation code consistent for create2 deployments
    function initialize(address _target, address _counterpart) public initializer {
        require(_target != address(0), "CNR: Target cannot be zero address");
        require(_counterpart != address(0), "CNR: Counterpart cannot be zero address");

        target = _target;
        counterpart = _counterpart;
    }

    fallback () external payable {
        if (msg.sender == target) {
            _forwardCrossDomainMessage();
        } else {
            _verifyCrossDomainSender();
            target.execute(msg.data, msg.value);
        }
    }

    receive () external payable {
        revert("Do not send ETH to this contract");
    }

    /* ========== Virtual functions ========== */

    function _forwardCrossDomainMessage() internal virtual;

    function _verifyCrossDomainSender() internal virtual;

    function getFee(uint256) external virtual view returns (uint256) {
        return 0;
    }
}
