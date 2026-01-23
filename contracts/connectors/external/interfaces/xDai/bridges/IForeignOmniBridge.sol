// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */

pragma solidity >0.6.12;

interface IForeignOmniBridge {
    function relayTokens(address token, address _receiver, uint256 _amount) external;
}
