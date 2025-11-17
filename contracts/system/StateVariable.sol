// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Pipe/AccesControlPipes.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";


contract stateVariable is AccesControl, Pausable {

// =============================================================
// Struct Definitions
// =============================================================

// 1 //
struct ComponentWeightPercentage {
    uint64 rewardScore;
    uint64 reputationScore;
    uint64 deadlineScore;
    uint64 revisionScore;
}

// 2 //
struct StakeAmount {
    uint256 low;
    uint256 midLow;
    uint256 mid;
    uint256 midHigh;
    uint256 high;
    uint256 ultraHigh;
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
struct StateVar {
    uint32 cooldownInHour;
    uint32 minRevisionTimeInHour; // stored in hours
    uint32 NegPenalty;            // percent (0..100)
    uint32 maxReward;             // input unit (ether)
    uint32 feePercentage;         // percent for creatorStake
    uint64 maxStake;              // upper limit for stake
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


// =============================================================
// State Variables
// =============================================================

ComponentWeightPercentage public componentWeightPercentages;   // 1
StakeAmount public stakeAmounts;                               // 2
ReputationPoint public reputationPoints;                       // 3
StateVar public StateVars;                                     // 4
StakeCategory public StakeCategorys;                           // 5

// ------------------------------------------------------------ Events ------------------------------------------------------------
event componentWeightPercentagesChanged(
    uint64 rewardScore,
    uint64 reputationScore,
    uint64 deadlineScore,
    uint64 revisionScore
);

event stakeAmountsChanged(
    uint256 low,
    uint256 midLow,
    uint256 mid,
    uint256 midHigh,
    uint256 high,
    uint256 ultraHigh
);

event reputationPointsChanged(
    uint32 CancelByMe,
    uint32 requestCancel,
    uint32 respondCancel,
    uint32 revision,
    uint32 taskAcceptCreator,
    uint32 taskAcceptMember,
    uint32 deadlineHitCreator,
    uint32 deadlineHitMember
);

event StateVarsChanged(
    uint32 cooldownInHour,
    uint32 minRevisionTimeInHour,
    uint32 NegPenalty,
    uint32 maxReward,
    uint32 feePercentage,
    uint64 maxStake,
    uint32 maxRevision
);

event stakeCategorysChanged(
    uint256 low,
    uint256 midleLow,
    uint256 midle,
    uint256 midleHigh,
    uint256 high,
    uint256 ultraHigh
);

event ContractPaused(address account);
event ContractUnpaused(address account);

// ------------------------------------------------------------ Errors ------------------------------------------------------------
error TotalMustBe10();
error InvalidMaxStakeAmount();

// ------------------------------------------------------- Constructor ------------------------------------------------------------

constructor(
    // --------------------------
    // (1) Component Weight
    // --------------------------
    uint64 _rewardScore,
    uint64 _reputationScore,
    uint64 _deadlineScore,
    uint64 _revisionScore,

    // --------------------------
    // (2) Stake Amount
    // --------------------------
    uint256 _stakeLow,
    uint256 _stakeMidLow,
    uint256 _stakeMid,
    uint256 _stakeMidHigh,
    uint256 _stakeHigh,
    uint256 _stakeUltraHigh,

    // --------------------------
    // (3) Reputation Point
    // --------------------------
    uint32 _cancelByMe,
    uint32 _requestCancel,
    uint32 _respondCancel,
    uint32 _revision,
    uint32 _taskAcceptCreator,
    uint32 _taskAcceptMember,
    uint32 _deadlineHitCreator,
    uint32 _deadlineHitMember,

    // --------------------------
    // (4) State Vars
    // --------------------------
    uint32 _cooldownInHour,
    uint32 _minRevisionTimeInHour,
    uint32 _negPenalty,
    uint32 _maxReward,
    uint32 _feePercentage,
    uint64 _maxStake,
    uint32 _maxRevision,

    // --------------------------
    // (5) Stake Category
    // --------------------------
    uint256 _catLow,
    uint256 _catMidleLow,
    uint256 _catMidle,
    uint256 _catMidleHigh,
    uint256 _catHigh,
    uint256 _catUltraHigh
) {

    // 1. Component Weight Percentage
    uint64 total = _rewardScore + _reputationScore + _deadlineScore + _revisionScore;
    if (total != 10) revert TotalMustBe10();

    componentWeightPercentages = ComponentWeightPercentage({
        rewardScore: _rewardScore,
        reputationScore: _reputationScore,
        deadlineScore: _deadlineScore,
        revisionScore: _revisionScore
    });

    // 2. Stake Amount
    stakeAmounts = StakeAmount({
        low: _stakeLow * 1 ether,
        midLow: _stakeMidLow * 1 ether,
        mid: _stakeMid * 1 ether,
        midHigh: _stakeMidHigh * 1 ether,
        high: _stakeHigh * 1 ether,
        ultraHigh: _stakeUltraHigh * 1 ether
    });

    // 3. Reputation Point
    reputationPoints = ReputationPoint({
        CancelByMe: _cancelByMe,
        requestCancel: _requestCancel,
        respondCancel: _respondCancel,
        revision: _revision,
        taskAcceptCreator: _taskAcceptCreator,
        taskAcceptMember: _taskAcceptMember,
        deadlineHitCreator: _deadlineHitCreator,
        deadlineHitMember: _deadlineHitMember
    });

    // 4. State Vars
    if (_maxStake > _catUltraHigh) revert InvalidMaxStakeAmount();

    StateVars = StateVar({
        cooldownInHour: _cooldownInHour,
        minRevisionTimeInHour: _minRevisionTimeInHour,
        NegPenalty: _negPenalty,
        maxReward: _maxReward,
        feePercentage: _feePercentage,
        maxStake: _maxStake * 1 ether,
        maxRevision: _maxRevision
    });

    // 5. Stake Category
    StakeCategorys = StakeCategory({
        low: _catLow,
        midleLow: _catMidleLow,
        midle: _catMidle,
        midleHigh: _catMidleHigh,
        high: _catHigh,
        ultraHigh: _catUltraHigh
    });
}

//-------------------------------------------------------------------------- Exported Functions --------------------------------------------------------------------------
// =============================================================
// 1. ComponentWeightPercentage Getters
// =============================================================

function __getRewardScore() external view returns (uint64) {
    return componentWeightPercentages.rewardScore;
}

function __getReputationScore() external view returns (uint64) {
    return componentWeightPercentages.reputationScore;
}

function __getDeadlineScore() external view returns (uint64) {
    return componentWeightPercentages.deadlineScore;
}

function __getRevisionScore() external view returns (uint64) {
    return componentWeightPercentages.revisionScore;
}


// =============================================================
// 2. StakeAmount Getters
// =============================================================

function __getStakeLow() external view returns (uint256) {
    return stakeAmounts.low;
}

function __getStakeMidLow() external view returns (uint256) {
    return stakeAmounts.midLow;
}

function __getStakeMid() external view returns (uint256) {
    return stakeAmounts.mid;
}

function __getStakeMidHigh() external view returns (uint256) {
    return stakeAmounts.midHigh;
}

function __getStakeHigh() external view returns (uint256) {
    return stakeAmounts.high;
}

function __getStakeUltraHigh() external view returns (uint256) {
    return stakeAmounts.ultraHigh;
}


// =============================================================
// 3. ReputationPoint Getters
// =============================================================

function __getCancelByMe() external view returns (uint32) {
    return reputationPoints.CancelByMe;
}

function __getRequestCancel() external view returns (uint32) {
    return reputationPoints.requestCancel;
}

function __getRespondCancel() external view returns (uint32) {
    return reputationPoints.respondCancel;
}

function __getRevisionPenalty() external view returns (uint32) {
    return reputationPoints.revision;
}

function __getTaskAcceptCreator() external view returns (uint32) {
    return reputationPoints.taskAcceptCreator;
}

function __getTaskAcceptMember() external view returns (uint32) {
    return reputationPoints.taskAcceptMember;
}

function __getDeadlineHitCreator() external view returns (uint32) {
    return reputationPoints.deadlineHitCreator;
}

function __getDeadlineHitMember() external view returns (uint32) {
    return reputationPoints.deadlineHitMember;
}


// =============================================================
// 4. StateVar Getters
// =============================================================

function __getCooldownInHour() external view returns (uint32) {
    return StateVars.cooldownInHour;
}

function __getMinRevisionTimeInHour() external view returns (uint32) {
    return StateVars.minRevisionTimeInHour;
}

function __getNegPenalty() external view returns (uint32) {
    return StateVars.NegPenalty;
}

function __getMaxReward() external view returns (uint32) {
    return StateVars.maxReward;
}

function __getFeePercentage() external view returns (uint32) {
    return StateVars.feePercentage;
}

function __getMaxStake() external view returns (uint64) {
    return StateVars.maxStake;
}

function __getMaxRevision() external view returns (uint32) {
    return StateVars.maxRevision;
}


// =============================================================
// 5. StakeCategory Getters
// =============================================================

function __getCategoryLow() external view returns (uint256) {
    return StakeCategorys.low;
}

function __getCategoryMidleLow() external view returns (uint256) {
    return StakeCategorys.midleLow;
}

function __getCategoryMidle() external view returns (uint256) {
    return StakeCategorys.midle;
}

function __getCategoryMidleHigh() external view returns (uint256) {
    return StakeCategorys.midleHigh;
}

function __getCategoryHigh() external view returns (uint256) {
    return StakeCategorys.high;
}

function __getCategoryUltraHigh() external view returns (uint256) {
    return StakeCategorys.ultraHigh;
}

//-------------------------------------------------------------------------- Admin Functions --------------------------------------------------------------------------

// =============================================================
// Setter Functions
// =============================================================

// 1 //
function setComponentWeightPercentage(
    uint64 _rewardScore,
    uint64 _reputationScore,
    uint64 _deadlineScore,
    uint64 _revisionScore
) external onlyEmployes whenNotPaused {
    uint64 Total = _rewardScore + _reputationScore + _deadlineScore + _revisionScore;
    if (Total != 10) revert TotalMustBe10();

    componentWeightPercentages = ComponentWeightPercentage({
        rewardScore: _rewardScore,
        reputationScore: _reputationScore,
        deadlineScore: _deadlineScore,
        revisionScore: _revisionScore
    });

    emit componentWeightPercentagesChanged(
        _rewardScore,
        _reputationScore,
        _deadlineScore,
        _revisionScore
    );
}

// 2 //
function setStakeAmount(
    uint256 _low,
    uint256 _midLow,
    uint256 _mid,
    uint256 _midHigh,
    uint256 _high,
    uint256 _ultraHigh
) external onlyEmployes whenNotPaused {
    stakeAmounts = StakeAmount({
        low: _low * 1 ether,
        midLow: _midLow * 1 ether,
        mid: _mid * 1 ether,
        midHigh: _midHigh * 1 ether,
        high: _high * 1 ether,
        ultraHigh: _ultraHigh * 1 ether
    });

    emit stakeAmountsChanged(
        _low,
        _midLow,
        _mid,
        _midHigh,
        _high,
        _ultraHigh
    );
}

// 3 //
function setReputationPoint(
    uint32 newCancelByMe,
    uint32 newRequestCancel,
    uint32 newRespondCancel,
    uint32 newRevision,
    uint32 newTaskAcceptCreator,
    uint32 newTaskAcceptMember,
    uint32 newDeadlineHitCreator,
    uint32 newDeadlineHitMember
) external onlyEmployes whenNotPaused {
    reputationPoints.CancelByMe = newCancelByMe;
    reputationPoints.requestCancel = newRequestCancel;
    reputationPoints.respondCancel = newRespondCancel;
    reputationPoints.revision = newRevision;
    reputationPoints.taskAcceptCreator = newTaskAcceptCreator;
    reputationPoints.taskAcceptMember = newTaskAcceptMember;
    reputationPoints.deadlineHitCreator = newDeadlineHitCreator;
    reputationPoints.deadlineHitMember = newDeadlineHitMember;

    emit reputationPointsChanged(
        newCancelByMe,
        newRequestCancel,
        newRespondCancel,
        newRevision,
        newTaskAcceptCreator,
        newTaskAcceptMember,
        newDeadlineHitCreator,
        newDeadlineHitMember
    );
}

// 4 //
function setStateVars(
    uint32 _cooldownInHour,
    uint32 _minRevisionTimeInHour,
    uint32 _NegPenalty,
    uint32 _maxReward,
    uint32 _feePercentage,
    uint64 _maxStake,
    uint32 _maxRevision
) external onlyEmployes whenNotPaused {
    if (_maxStake > StakeCategorys.ultraHigh) revert InvalidMaxStakeAmount();

    StateVars = StateVar({
        cooldownInHour: _cooldownInHour,
        minRevisionTimeInHour: _minRevisionTimeInHour,
        NegPenalty: _NegPenalty,
        maxReward: _maxReward,
        feePercentage: _feePercentage,
        maxStake: _maxStake * 1 ether,
        maxRevision: _maxRevision
    });

    emit StateVarsChanged(
        _cooldownInHour,
        _minRevisionTimeInHour,
        _NegPenalty,
        _maxReward,
        _feePercentage,
        _maxStake,
        _maxRevision
    );
}

// 5 //
function setStakeCategory(
    uint256 _low,
    uint256 _midleLow,
    uint256 _midle,
    uint256 _midleHigh,
    uint256 _high,
    uint256 _ultraHigh
) external onlyEmployes whenNotPaused {
    StakeCategorys = StakeCategory({
        low: _low,
        midleLow: _midleLow,
        midle: _midle,
        midleHigh: _midleHigh,
        high: _high,
        ultraHigh: _ultraHigh
    });

    emit stakeCategorysChanged(
        _low,
        _midleLow,
        _midle,
        _midleHigh,
        _high,
        _ultraHigh
    );
}

    function pause() external onlyEmployes {
    _pause();
    emit ContractPaused(msg.sender);
    }
    function unpause() external onlyEmployes {
    _unpause();
    emit ContractUnpaused(msg.sender);
    }

}