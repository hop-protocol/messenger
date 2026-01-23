// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

import "../Connector.sol";
import "./polygon/ReentrancyGuard.sol";
import "./polygon/tunnel/FxBaseChildTunnel.sol";

contract L2PolygonConnector is Connector, FxBaseChildTunnel, ReentrancyGuard {
    constructor(address fxChild) FxBaseChildTunnel(fxChild) {}

    function _forwardCrossDomainMessage() internal override {
        _sendMessageToRoot(msg.data);
    }

    function _verifyCrossDomainSender() internal override view {
        revert InvalidCounterpart(msg.sender);
    }

    function _processMessageFromRoot(
        uint256 /* stateId */,
        address sender,
        bytes memory data
    )
        internal
        override
        validateSender(sender)
        nonReentrant
    {
        (bool success,) = target.call(data);
        require(success, "CNR: Failed to forward message");
    }
}
