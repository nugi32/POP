// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

interface IStateVar {

    // =============================================================
    // 1. ComponentWeightPercentage Getters
    // =============================================================

    function ___getRewardScore() external view returns (uint64);
    function ___getReputationScore() external view returns (uint64);
    function ___getDeadlineScore() external view returns (uint64);
    function ___getRevisionScore() external view returns (uint64);

    // =============================================================
    // 2. StakeAmount Getters
    // =============================================================

    function ___getStakeLow() external view returns (uint64);
    function ___getStakeMidLow() external view returns (uint64);
    function ___getStakeMid() external view returns (uint32);
    function ___getStakeMidHigh() external view returns (uint32);
    function ___getStakeHigh() external view returns (uint32);
    function ___getStakeUltraHigh() external view returns (uint32);

    // =============================================================
    // 3. ReputationPoint Getters
    // =============================================================

    function ___getCancelByMe() external view returns (uint32);
    function ___getRequestCancel() external view returns (uint32);
    function ___getRespondCancel() external view returns (uint32);
    function ___getRevisionPenalty() external view returns (uint32);
    function ___getTaskAcceptCreator() external view returns (uint32);
    function ___getTaskAcceptMember() external view returns (uint32);
    function ___getDeadlineHitCreator() external view returns (uint32);
    function ___getDeadlineHitMember() external view returns (uint32);

    // =============================================================
    // 4. StateVar Getters
    // =============================================================

    function ___getCooldownInHour() external view returns (uint64);
    function ___getMinRevisionTimeInHour() external view returns (uint32);
    function ___getNegPenalty() external view returns (uint32);
    function ___getMaxReward() external view returns (uint32);
    function ___getFeePercentage() external view returns (uint32);
    function ___getMaxStake() external view returns (uint32);
    function ___getMaxRevision() external view returns (uint32);

    // =============================================================
    // 5. StakeCategory Getters
    // =============================================================

    function ___getCategoryLow() external view returns (uint256);
    function ___getCategoryMidleLow() external view returns (uint256);
    function ___getCategoryMidle() external view returns (uint256);
    function ___getCategoryMidleHigh() external view returns (uint256);
    function ___getCategoryHigh() external view returns (uint256);
    function ___getCategoryUltraHigh() external view returns (uint256);
}


abstract contract StateVarPipes is Initializable {

    IStateVar public stateVar;

    // 1 //
    struct ComponentWeightPercentage {
        uint64 rewardScore;
        uint64 reputationScore;
        uint64 deadlineScore;
        uint64 revisionScore;
    }

    // 2 //
    struct StakeAmount {
        uint64 low;
        uint64 midLow;
        uint32 mid;
        uint32 midHigh;
        uint32 high;
        uint32 ultraHigh;
    }

    // 3 //
    struct ReputationPoint {
        uint32 CancelByMe;
        uint32 requestCancel;
        uint32 respondCancel;
        uint32 revision;
        uint32 taskAcceptCreator;
        uint32 taskAcceptMember;
        uint32 deadlineHitCreator;
        uint32 deadlineHitMember;
    }

    // 4 //
    struct StateVariables {
        uint64 cooldownInHour;
        uint32 minRevisionTimeInHour;
        uint32 NegPenalty;
        uint32 maxReward;
        uint32 feePercentage;
        uint32 maxStake;
        uint32 maxRevision;
    }

    // 5 //
    struct StakeCategory {
        uint256 low;
        uint256 midleLow;
        uint256 midle;
        uint256 midleHigh;
        uint256 high;
        uint256 ultraHigh;
    }

    // State storage
    ComponentWeightPercentage internal componentWeightPercentages;
    StakeAmount internal stakeAmounts;
    ReputationPoint internal reputationPoints;
    StateVariables internal StateVars;
    StakeCategory internal StakeCategorys;

    // =============================================================
    // 1. ComponentWeightPercentage Getters
    // =============================================================
    function ___getRewardScore() internal view returns (uint64) {
        return componentWeightPercentages.rewardScore;
    }

    function ___getReputationScore() internal view returns (uint64) {
        return componentWeightPercentages.reputationScore;
    }

    function ___getDeadlineScore() internal view returns (uint64) {
        return componentWeightPercentages.deadlineScore;
    }

    function ___getRevisionScore() internal view returns (uint64) {
        return componentWeightPercentages.revisionScore;
    }

    // =============================================================
    // 2. StakeAmount Getters
    // =============================================================
    function ___getStakeLow() internal view returns (uint64) {
        return stakeAmounts.low;
    }

    function ___getStakeMidLow() internal view returns (uint64) {
        return stakeAmounts.midLow;
    }

    function ___getStakeMid() internal view returns (uint32) {
        return stakeAmounts.mid;
    }

    function ___getStakeMidHigh() internal view returns (uint32) {
        return stakeAmounts.midHigh;
    }

    function ___getStakeHigh() internal view returns (uint32) {
        return stakeAmounts.high;
    }

    function ___getStakeUltraHigh() internal view returns (uint32) {
        return stakeAmounts.ultraHigh;
    }

    // =============================================================
    // 3. ReputationPoint Getters
    // =============================================================
    function ___getCancelByMe() internal view returns (uint32) {
        return reputationPoints.CancelByMe;
    }

    function ___getRequestCancel() internal view returns (uint32) {
        return reputationPoints.requestCancel;
    }

    function ___getRespondCancel() internal view returns (uint32) {
        return reputationPoints.respondCancel;
    }

    function ___getRevisionPenalty() internal view returns (uint32) {
        return reputationPoints.revision;
    }

    function ___getTaskAcceptCreator() internal view returns (uint32) {
        return reputationPoints.taskAcceptCreator;
    }

    function ___getTaskAcceptMember() internal view returns (uint32) {
        return reputationPoints.taskAcceptMember;
    }

    function ___getDeadlineHitCreator() internal view returns (uint32) {
        return reputationPoints.deadlineHitCreator;
    }

    function ___getDeadlineHitMember() internal view returns (uint32) {
        return reputationPoints.deadlineHitMember;
    }

    // =============================================================
    // 4. StateVar Getters
    // =============================================================
    function ___getCooldownInHour() internal view returns (uint64) {
        return StateVars.cooldownInHour;
    }

    function ___getMinRevisionTimeInHour() internal view returns (uint32) {
        return StateVars.minRevisionTimeInHour;
    }

    function ___getNegPenalty() internal view returns (uint32) {
        return StateVars.NegPenalty;
    }

    function ___getMaxReward() internal view returns (uint32) {
        return StateVars.maxReward;
    }

    function ___getFeePercentage() internal view returns (uint32) {
        return StateVars.feePercentage;
    }

    function ___getMaxStake() internal view returns (uint32) {
        return StateVars.maxStake;
    }

    function ___getMaxRevision() internal view returns (uint32) {
        return StateVars.maxRevision;
    }

    // =============================================================
    // 5. StakeCategory Getters
    // =============================================================
    function ___getCategoryLow() internal view returns (uint256) {
        return StakeCategorys.low;
    }

    function ___getCategoryMidleLow() internal view returns (uint256) {
        return StakeCategorys.midleLow;
    }

    function ___getCategoryMidle() internal view returns (uint256) {
        return StakeCategorys.midle;
    }

    function ___getCategoryMidleHigh() internal view returns (uint256) {
        return StakeCategorys.midleHigh;
    }

    function ___getCategoryHigh() internal view returns (uint256) {
        return StakeCategorys.high;
    }

    function ___getCategoryUltraHigh() internal view returns (uint256) {
        return StakeCategorys.ultraHigh;
    }
}
