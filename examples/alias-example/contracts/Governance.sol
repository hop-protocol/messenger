// SPDX-License-Identifier: MIT
/**
 * @notice This contract is provided as-is without any warranties.
 * @dev No guarantees are made regarding security, correctness, or fitness for any purpose.
 * Use at your own risk.
 */
pragma solidity ^0.8.2;

import "@hop-protocol/messenger/contracts/aliases/AliasDispatcher.sol";

contract Governance {
    address public aliasDisptacher;

    function setAliasDispatcher(address _aliasDisptacher) external {
        aliasDisptacher = _aliasDisptacher;
    }

    function setCrossChainGreeting(uint256 toChainId, address greeter, string calldata greeting) external payable {
        // Get the encoded the cross-chain message
        bytes memory data = abi.encodeWithSignature(
            "setGreeting(string)",
            greeting
        );

        // Call `dispatchMessage` on this contract's the AliasDispatcher contract
        AliasDispatcher(aliasDisptacher).dispatchMessage{value: msg.value}(
            toChainId,
            greeter,
            data
        );
    }
}