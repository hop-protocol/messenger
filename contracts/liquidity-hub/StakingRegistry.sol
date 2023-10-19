//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SlidingWindowLib, SlidingWindow} from "./libraries/SlidingWindowLib.sol";

contract StakingRegistry is Ownable {
    using SafeERC20 for IERC20;
    using SlidingWindowLib for SlidingWindow;

    struct Stake {
        uint256 hopStake;
        uint256 totalUnstakedHop;
        SlidingWindow pendingUnstakedHop;

        uint256 challengeCount;
    }

    struct Challenge {
        address staker;
        address challenger;
        bytes32 role;
        uint256 lastUpdated;
        uint256 penalty;
        bool isSettled;
        bool isAppealed;
        uint256 challengeEth;
        uint256 appealEth;
        address winner;
    }

    uint256 public challengePeriod = 3 days;
    uint256 public appealPeriod = 1 days;
    uint256 public minChallengeIncrease = 1 ether;
    uint256 public fullAppeal = 10 ether;

    IERC20 private hopToken;
    mapping(bytes32 => uint256) public minHopStakeForRole;
    mapping(bytes32 => mapping(address => Stake)) private stakes;
    mapping(bytes32 => Challenge) public challenges;
    mapping(address => uint256) public withdrawableEth;

    function initRole(bytes32 role, uint256 minStake) public onlyOwner {
        minHopStakeForRole[role] = minStake;
    }

    function stakeHop(bytes32 role, address staker, uint256 amount) public {
        uint256 minHopStake = minHopStakeForRole[role];
        require(amount >= minHopStake, "StakeRegistry: insufficient stake");
        hopToken.safeTransferFrom(staker, address(this), amount);

        Stake storage stake = stakes[role][staker];
        stake.hopStake += amount;
    }

    function unstakeHop(bytes32 role, uint256 amount) public {
        Stake storage stake = stakes[role][msg.sender];

        uint256 currentStake = stake.hopStake;
        if (currentStake != amount) {
            uint256 minHopStake = minHopStakeForRole[role];
            require(currentStake >= amount + minHopStake, "StakeRegistry: insufficient balance");
        }

        stake.hopStake -= amount;
        stake.totalUnstakedHop += amount;
        stake.pendingUnstakedHop.add(block.timestamp, amount);
    }

    function withdraw(bytes32 role, address staker) public {
        Stake storage stake = stakes[role][staker];
        uint256 withdrawableBalance = getWithdrawableBalance(role, staker);
        stake.totalUnstakedHop -= withdrawableBalance;
        hopToken.safeTransfer(staker, withdrawableBalance);
    }

    function createChallenge(
        address staker,
        bytes32 role,
        uint256 penalty,
        bytes memory slashingData
    )
        public
        payable
        returns (bytes32)
    {
        address challenger = msg.sender;
        bytes32 challengeId = getChallengeId(role, staker, penalty, challenger, slashingData);
        require(staker != address(0), "StakeRegistry: no zero address");
        require(challenges[challengeId].staker == address(0), "StakeRegistry: challenge already exists");
        require(challenges[challengeId].challengeEth == 0, "StakeRegistry: challenge stake already exists");
        uint256 challengeEth = msg.value;
        require(challengeEth >= minChallengeIncrease, "StakeRegistry: insufficient challenge stake");

        challenges[challengeId] = Challenge(
            staker,
            challenger,
            role,
            block.timestamp,
            penalty,
            false,
            false,
            challengeEth,
            0,
            address(0)
        );

        challenges[challengeId].challengeEth = challengeEth;

        stakes[role][staker].challengeCount += 1;

        return challengeId;
    }

    function addToChallenge(
        address staker,
        address challenger,
        bytes32 role,
        uint256 penalty,
        bytes memory slashingData
    )
        public
        payable
    {
        bytes32 challengeId = getChallengeId(role, staker, penalty, challenger, slashingData);
        Challenge storage challenge = challenges[challengeId];
        require(challenge.challenger != address(0), "StakeRegistry: challenge does not exists");
        require(challenge.isSettled == false, "StakeRegistry: challenge already isSettled");
        uint256 currentAppealEth = challenge.appealEth;
        require(currentAppealEth < fullAppeal, "StakeRegistry: appeal is full");

        require(msg.value > minChallengeIncrease, "StakeRegistry: insufficient ETH for challenge");
        uint256 challengeEth = challenge.challengeEth + msg.value;
        require(challengeEth > challenge.appealEth, "StakeRegistry: insufficient appeal ETH");
        challenge.challengeEth = challengeEth;

        if (challenge.isAppealed) {
            challenge.lastUpdated = block.timestamp;
            challenge.isAppealed = false;
            stakes[role][staker].challengeCount += 1;
        }
    }

    function addToAppeal(
        address staker,
        address challenger,
        bytes32 role,
        uint256 penalty,
        bytes memory slashingData
    )
        public
        payable
    {
        bytes32 challengeId = getChallengeId(role, staker, penalty, challenger, slashingData);
        Challenge storage challenge = challenges[challengeId];
        require(challenge.staker != address(0), "StakeRegistry: challenge does not exists");
        require(challenge.isSettled == false, "StakeRegistry: challenge already isSettled");
        uint256 currentAppealEth = challenge.appealEth;
        require(currentAppealEth < fullAppeal, "StakeRegistry: appeal is full");

        uint256 fullAppealAmountNeeded = fullAppeal - currentAppealEth;
        require(msg.value > minChallengeIncrease || msg.value >= fullAppealAmountNeeded, "StakeRegistry: insufficient ETH for appeal");

        challenge.appealEth = currentAppealEth + msg.value;

        if (!challenge.isAppealed) {
            challenge.lastUpdated = block.timestamp;
            challenge.isAppealed = true;

            Stake storage stake = stakes[role][staker];
            assert(stake.challengeCount > 0);
            stake.challengeCount -= 1;
        }
    }

    function optimisticallySettleChallenge(
        address staker,
        address challenger,
        bytes32 role,
        uint256 penalty,
        bytes memory slashingData
    )
        public
        onlyOwner
    {
        bytes32 challengeId = getChallengeId(role, staker, penalty, challenger, slashingData);
        Challenge storage challenge = challenges[challengeId];
        require(challenge.staker != address(0), "StakeRegistry: challenge does not exists");
        require(challenge.isSettled == false, "StakeRegistry: challenge already isSettled");
        uint256 currentAppealEth = challenge.appealEth;
        require(currentAppealEth < fullAppeal, "StakeRegistry: appeal is full");
        require(block.timestamp > challenge.lastUpdated + challengePeriod, "StakeRegistry: challengePeriod not passed");
        challenge.isSettled = true;

        uint256 challengeEth = challenge.challengeEth;
        uint256 appealEth = challenge.appealEth;
        uint256 totalEth = challengeEth + appealEth;

        if (challenge.isAppealed) {
            // Challenge is unsuccessful
            uint256 ethForStaker = (challengeEth / 2) + appealEth;
            uint256 ethForHopDao = challengeEth - ethForStaker;

            withdrawableEth[staker] += ethForStaker;
            withdrawableEth[owner()] += ethForHopDao;
        } else {
            // Challenge is successful
            uint256 hopForChallenger = penalty / 2;
            uint256 hopForDao = penalty - hopForChallenger;

            Stake storage stake = stakes[role][staker];
            stake.hopStake -= penalty;
            assert(stake.challengeCount > 0);
            stake.challengeCount -= 1;

            hopToken.safeTransfer(owner(), hopForDao);
            hopToken.safeTransfer(challenge.challenger, hopForChallenger);
            withdrawableEth[challenge.challenger] += totalEth;
        }
    }

    function acceptSlash(
        address challenger,
        bytes32 role,
        uint256 penalty,
        bytes memory slashingData
    )
        public
        payable
    {
        address staker = msg.sender;
        bytes32 challengeId = getChallengeId(role, staker, penalty, challenger, slashingData);
        Challenge storage challenge = challenges[challengeId];
        require(challenge.staker != address(0), "StakeRegistry: challenge does not exists");
        require(challenge.isSettled == false, "StakeRegistry: challenge already isSettled");
        challenge.isSettled = true;

        // Stake storage stake = stakes[role][staker];
        uint256 challengeEth = challenge.challengeEth;
        uint256 appealEth = challenge.appealEth;
        uint256 totalEth = challengeEth + appealEth;

        // Challenge is successful
        uint256 hopForChallenger = penalty / 2;
        uint256 hopForDao = penalty - hopForChallenger;

        Stake storage stake = stakes[role][staker];
        stake.hopStake -= penalty;
        assert(stake.challengeCount > 0);
        stake.challengeCount -= 1;

        hopToken.safeTransfer(owner(), hopForDao);
        hopToken.safeTransfer(challenge.challenger, hopForChallenger);
        withdrawableEth[challenge.challenger] += totalEth;
    }

    function forceSettleChallenge() public onlyOwner {
        // ToDo
    }

    function isStaked(bytes32 role, address staker) public view returns (bool) {
        Stake storage stake = stakes[role][staker];
        if (stake.challengeCount > 0) return false;

        uint256 minHopStake = minHopStakeForRole[role];
        uint256 hopStake = stake.hopStake;
        if (hopStake < minHopStake) return false;

        return true;
    }

    function getStakedBalance(
        bytes32 role,
        address staker
    )
        public
        view
        returns (uint256)
    {
        return stakes[role][staker].hopStake;
    }

    function getWithdrawableBalance(bytes32 role, address staker) public view returns (uint256) {
        Stake storage stake = stakes[role][staker];
        SlidingWindow storage pendingSlidingWindow = stake.pendingUnstakedHop;
        uint256 challengeStartTime = block.timestamp - challengePeriod;
        uint256 pendingUnstakedHop = pendingSlidingWindow.totalSince(challengeStartTime);
        uint256 totalUnstakedHop = stake.totalUnstakedHop;
        if (pendingUnstakedHop >= totalUnstakedHop) return 0;
        return totalUnstakedHop - pendingUnstakedHop;
    }

    function getRoleForRoleName(string memory roleName) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(roleName));
    }

    function getChallengeId(
        bytes32 role,
        address staker,
        uint256 penalty,
        address challenger,
        bytes memory slashingData
    )
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(role, staker, penalty, challenger, slashingData));
    }
}
