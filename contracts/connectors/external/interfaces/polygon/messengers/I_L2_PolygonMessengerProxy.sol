// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */

pragma solidity >0.6.0;

interface I_L2_PolygonMessengerProxy {
    function sendCrossDomainMessage(bytes memory _calldata) external;
    function xDomainMessageSender() external view returns (address);
    function processMessageFromRoot(
        bytes calldata message
    ) external;
}