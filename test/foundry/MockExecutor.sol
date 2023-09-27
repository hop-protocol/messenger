//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "../../contracts/ERC5164/IMessageExecutor.sol";

contract MockExecutor is IMessageExecutor {
    function execute(
        bytes32 messageId,
        uint256 fromChainId,
        address from,
        address to,
        bytes memory data
    )
        public
    {
        (bool success, bytes memory returnData) = to.call(
            abi.encodePacked(data, messageId, fromChainId, from)
        );

        if (success) {
            emit MessageIdExecuted(fromChainId, messageId);
        } else {
            revert MessageFailure(messageId, returnData);
        }
    }
}