//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SlidingWindowLib, SlidingWindow} from "./SlidingWindowLib.sol";
import {IMessageDispatcher} from "../../ERC5164/IMessageDispatcher.sol";
import {IMessageExecutor} from "../../ERC5164/IMessageExecutor.sol";
import {ICrossChainFees} from "../../messenger/interfaces/ICrossChainFees.sol";

struct TokenBus {
    IERC20 token;
    IERC20 counterpartToken;
    uint256 counterpartChainId;
    uint256 rateDelta;

    uint256 feeBalance;

    uint256 totalSent;
    bytes32[] checkpoints;
    mapping(bytes32 => uint256) totalSentAtCheckpoint;

    uint256 totalClaims;
    bytes32[] claimCheckpoints;
    mapping(bytes32 => uint256) totalClaimsAtCheckpoint;

    uint256 totalWithdrawn;
    uint256 totalWithdrawable;
    SlidingWindow pendingWithdrawable;

    mapping(bytes32 => uint256) claimPostedAt;
    mapping(address => uint256) balance;
    mapping(address => SlidingWindow) pendingBalances;
    mapping(address => SlidingWindow) minTotalSent;
}

library TokenBusLib {
    using SlidingWindowLib for SlidingWindow;
    using TokenBusLib for TokenBus;
    using SafeCast for uint256;
    using SafeCast for int256;

    // on deposit
    function calcFee(TokenBus storage tokenBus, uint256 amount, uint256 attestedTotalSent) internal view returns (uint256) {
        // if there is enough surplus for the claim, return 0 fee
        uint256 totalSent = tokenBus.totalSent;
        if (attestedTotalSent > totalSent + amount) return 0;

        uint256 startDeficit = attestedTotalSent - totalSent;
        uint256 endDeficit = 0;
        if (startDeficit > amount) {
            endDeficit = startDeficit - amount;
        }

        uint256 avgDeficit = (startDeficit + endDeficit) / 2;
        uint256 rate = avgDeficit * tokenBus.rateDelta / 10e18;
        uint256 fee = amount * rate / 10e18;

        return fee;
    }

    // on withdrawal
    function calcBonus(TokenBus storage tokenBus, uint256 amount, uint256 totalSent, uint256 attestedTotalSent) internal view returns (uint256) {
        // if liquidity was freed, calculate the bonus
        if (totalSent >= attestedTotalSent) return 0;

        uint256 endDeficit = attestedTotalSent - totalSent;
        uint256 startDeficit = 0;
        if (endDeficit > amount) {
            startDeficit = endDeficit - amount;
        }

        uint256 avgDeficit = (startDeficit + endDeficit) / 2;
        uint256 rate = avgDeficit * tokenBus.rateDelta / 10e18;
        uint256 bonus = amount * rate / 10e18;

        return bonus;
    }

    function getTokenBusId(uint256 chainId0, IERC20 token0, uint256 chainId1, IERC20 token1) internal pure returns (bytes32) {
        bool isAssending = chainId0 < chainId1;

        uint256 chainIdA = isAssending ? chainId0 : chainId1;
        uint256 chainIdB = isAssending ? chainId1 : chainId0;
        IERC20 tokenA = isAssending ? token0 : token1;
        IERC20 tokenB = isAssending ? token1 : token0;

        return keccak256(abi.encodePacked(chainIdA, tokenA, chainIdB, tokenB));
    }

    function getWithdrawableBalance(TokenBus storage tokenBus, address recipient, uint256 time) internal view returns (uint256) {
        uint256 pendingBalances = tokenBus.pendingBalances[recipient].get(time); // ToDo: get all pending claims since window
        uint256 balance = tokenBus.balance[recipient];

        uint256 withdrawableBalance = balance - pendingBalances;

        uint256 claimsSent = tokenBus.totalSent;
        uint256 minClaimsSent = tokenBus.minTotalSent[recipient].get(time);
        if (claimsSent < minClaimsSent) {
            return 0;
        } else {
            return withdrawableBalance;
        }

        return 0;
    }
}