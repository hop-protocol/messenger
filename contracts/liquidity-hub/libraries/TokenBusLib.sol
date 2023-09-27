//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SlidingWindowLib, SlidingWindow} from "./SlidingWindowLib.sol";
import {IMessageDispatcher} from "../../ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../../ERC5164/IMessageExecutor.sol";
import {ICrossChainFees} from "../../messenger/interfaces/ICrossChainFees.sol";

struct TokenBus {
    IERC20 token;
    IERC20 counterpartToken;
    uint256 counterpartChainId;
    uint256 claimsSent;
    uint256 claimsReceived;
    mapping(bytes32 => bool) claimPosted;
    mapping(address => uint256) balance;
    mapping(address => SlidingWindow) pendingBalances;
    mapping(address => SlidingWindow) minClaimsSent;
}

library TokenBusLib {
    using SlidingWindowLib for SlidingWindow;
    using TokenBusLib for TokenBus;

    function getTokenBusId(uint256 chainId0, IERC20 token0, uint256 chainId1, IERC20 token1) internal pure returns (bytes32) {
        bool isAssending = chainId0 < chainId1;

        uint256 chainIdA = isAssending ? chainId0 : chainId1;
        uint256 chainIdB = isAssending ? chainId1 : chainId0;
        IERC20 tokenA = isAssending ? token0 : token1;
        IERC20 tokenB = isAssending ? token1 : token0;

        return keccak256(abi.encodePacked(chainIdA, tokenA, chainIdB, tokenB));
    }

    function withdrawClaims(TokenBus storage tokenBus, address recipient, uint256 window) internal {
        uint256 withdrawalAmount = tokenBus.getWithdrawableBalance(recipient, window);
        tokenBus.balance[recipient] -= withdrawalAmount;
        IERC20(tokenBus.token).transfer(recipient, withdrawalAmount);
    }

    function getWithdrawableBalance(TokenBus storage tokenBus, address recipient, uint256 window) internal view returns (uint256) {
        uint256 pendingBalances = tokenBus.pendingBalances[recipient].get(window); // ToDo: get all pending claims since window
        uint256 balance = tokenBus.balance[recipient];

        uint256 withdrawableBalance = balance - pendingBalances;

        uint256 claimsSent = tokenBus.claimsSent;
        uint256 minClaimsSent = tokenBus.minClaimsSent[recipient].get(window);
        if (claimsSent < minClaimsSent) {
            return 0;
        } else {
            return withdrawableBalance;
        }
    }
}