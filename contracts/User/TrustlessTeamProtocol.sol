// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Logic/AccesControl.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title TrustlessTeamProtocol v2 (Patched, documented)
 * @author nugi
 * @notice Protocol to create tasks, allow registration/joining, staking and pull-pay reward flows with reputation.
 * @dev Upgradeable contract (UUPS). Uses AccesControl for owner/employee/user roles.
 *
 * Key design points:
 *  - Pull payments: users call withdraw() to claim funds.
 *  - Creator provides reward (in ETH), plus creatorStake and fee in msg.value when creating task.
 *  - Member stakes when requesting to join (stake is returned/used depending on outcome).
 *  - Deadlines are handled via timestamp `deadlineAt`.
 *  - Reputation points and counters are tracked per-user.
 *  - Fee (protocol share) stored in `feeCollected` and withdrawn manually by employees.
 */
contract TrustlessTeamProtocol is
    Initializable,
    AccesControl,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    // =============================================================
    // ENUMS
    // =============================================================

    /// @notice Task lifecycle status
    enum TaskStatus { NonExistent, Active, OpenRegistration, InProgres, CancelRequested, Completed, Cancelled }

    /// @notice Join/submission state per user relative to a task
    enum UserTask { None, Request, Accepted, Submitted, Revision, Cancelled }

    /// @notice Cancel request status
    enum TaskRejectRequest { None, Pending }

    /// @notice Submission status
    enum SubmitStatus { NoneStatus, Pending, RevisionNeeded, Accepted }

    // =============================================================
    // STRUCTS
    // =============================================================

    /// @notice Core task data
    struct Task {
        uint256 taskId;
        TaskStatus status;
        address creator;
        address member;
        string title;
        string githubURL;
        uint256 reward; // wei
        uint32 deadlineHours; // configured hours input
        uint256 deadlineAt; // unix timestamp when deadline triggers
        uint256 createdAt;
        uint256 creatorStake; // wei
        uint256 memberStake; // wei
        uint8 maxRevision;
        bool isMemberStakeLocked;
        bool isCreatorStakeLocked;
        bool isRewardClaimed;
        bool exists;
    }

    /// @notice Applicant join request
    struct JoinRequest {
        address applicant;
        uint256 stakeAmount;
        UserTask status;
        bool isPending;
        bool hasWithdrawn;
    }

    /// @notice Cancel negotiation struct
    struct CancelRequest {
        address requester;
        address counterparty;
        uint256 expiry;
        TaskRejectRequest status;
        string reason;
    }

    /// @notice Submit record for a task
    struct TaskSubmit {
        string githubURL;
        address sender;
        string note;
        SubmitStatus status;
        uint8 revisionTime;
        uint256 newDeadline; // timestamp
    }

    /// @notice Reputation and penalty configuration
    struct reputationPoint {
        uint32 CancelByMe;
        uint32 requestCancel;
        uint32 respondCancel;
        uint32 revision;
        uint32 taskAcceptCreator;
        uint32 taskAcceptMember;
        uint32 deadlineHitCreator;
        uint32 deadlineHitMember;
    }

    /// @notice global state variables configuration
    struct StateVar {
        uint64 cooldownInHour;
        uint32 minRevisionTimeInHour; // stored in hours
        uint32 NegPenalty; // percent (0..100)
        uint32 maxReward; // input unit (ether)
        uint32 feePercentage; // percent for creatorStake
        uint32 maxStake; // upper limit for stake (business unit)
        uint32 maxRevision;
    }

    /// @notice simple user model local to this contract
    struct User {
        uint256 totalTasksCreated;
        uint256 totalTasksCompleted;
        uint256 totalTasksFailed;
        uint32 reputation;
        uint8 age;
        bool isRegistered;
        string name;
    }

    // =============================================================
    // STATE
    // =============================================================

    // Users & reputation
    mapping(address => User) internal Users;

    // Submissions & withdrawable balances
    mapping(uint256 => TaskSubmit) internal TaskSubmits;
    mapping(address => uint256) public withdrawable;

    // Tasks & join/cancel requests
    mapping(uint256 => Task) public Tasks;
    mapping(uint256 => JoinRequest[]) public joinRequests;
    mapping(uint256 => CancelRequest) internal CancelRequests;

    // Config / system
    reputationPoint public reputationPoints;
    StateVar public StateVars;

    uint256 public taskCounter;
    uint256 internal feeCollected;
    uint256 public algoConstant; // scaling factor used in stake formula
    address payable public systemWallet;

    // Storage gap for upgradeability
    uint256[40] private ___gap;

    // =============================================================
    // EVENTS
    // =============================================================

    // User events
    event UserRegistered(address indexed user, string name, uint8 age);
    event UserUnregistered(address indexed user, string name, uint8 age);

    // Task lifecycle events
    event TaskCreated(string title, uint256 indexed taskId, address indexed creator, uint256 reward, uint256 creatorStake);
    event RegistrationOpened(uint256 indexed taskId);
    event RegistrationClosed(uint256 indexed taskId);
    event JoinRequested(uint256 indexed taskId, address indexed applicant, uint256 stakeAmount);
    event JoinApproved(uint256 indexed taskId, address indexed applicant);
    event JoinRejected(uint256 indexed taskId, address indexed applicant);
    event CancelRequestedEvent(uint256 indexed taskId, address indexed requester, string reason, uint256 cooldown);
    event CancelResponded(uint256 indexed taskId, bool approved);
    event TaskCancelledByMe(uint256 indexed taskId, address indexed initiator);
    event TaskSubmitted(uint256 indexed taskId, address indexed member, string githubURL);
    event TaskReSubmitted(uint256 indexed taskId, address indexed member);
    event TaskApproved(uint256 indexed taskId);
    event RevisionRequested(uint256 indexed taskId, uint8 revisionCount, uint256 newDeadline);
    event DeadlineTriggered(uint256 indexed taskId);

    // Payments / system
    event Withdrawal(address indexed user, uint256 amount);
    event CooldownChanged(uint64 newCooldown);
    event MaxStakeChanged(uint32 newMaxStake);
    event AlgoConstantChanged(uint256 newK);
    event SystemWalletChanged(address newWallet);
    event FeeWithdrawnToSystemWallet(uint256 amount);
    event ContractPaused(address indexed caller);
    event ContractUnpaused(address indexed caller);

    // =============================================================
    // ERRORS (custom, cheaper than strings)
    // =============================================================

    error TaskDoesNotExist();
    error NotTaskCreator();
    error NotTaskMember();
    error AlreadyRequestedJoin();
    error TaskNotOpen();
    error CancelAlreadyRequested();
    error NoActiveCancelRequest();
    error NotCounterparty();
    error InsufficientStake();
    error StakeHitLimit();
    error CancelOnlyWhenMemberAssigned();
    error TaskNotSubmittedYet();
    error InvalidTitle();
    error InvalidGithubURL();
    error InvalidDeadline();
    error TooManyRevisions();
    error InvalidRewardAmount();
    error InvalidReason();

    //submision
    error InvalidNote();

    //user register
    error AlredyRegistered();
    error InvalidName();
    error InvalidAge();
    error NotRegistered();

//  // =============================================================
    // MODIFIERS
    // =============================================================

    modifier taskExists(uint256 _taskId) {
        if (!Tasks[_taskId].exists) revert TaskDoesNotExist();
        _;
    }

    modifier onlyTaskCreator(uint256 _taskId) {
        if (Tasks[_taskId].creator != msg.sender) revert NotTaskCreator();
        _;
    }

    modifier onlyTaskMember(uint256 _taskId) {
        if (Tasks[_taskId].member != msg.sender) revert NotTaskMember();
        _;
    }

    modifier onlyRegistered() {
        if (!Users[msg.sender].isRegistered) revert NotRegistered();
        _;
    }
//
    // =============================================================
    // INITIALIZER
    // =============================================================

    /**
     * @notice Initialize protocol parameters and reputation points.
     * @dev Must be called once after deployment (proxy initialize).
     * @param _employeeAssignment address of central employee assignment (set in AccesControl)
     * @param _systemWallet payable address for fee withdrawals
     * @param _cooldownInHour cooldown window in hours for cancel negotiation
     * @param _maxStake maximum allowed stake (business-defined unit)
     * @param _NegPenalty negative penalty percentage (0..100)
     * @param _maxReward max reward (input unit, ether)
     * @param _minRevisionTimeInHour minimum hours for revision deadlines
     * @param _feePercentage fee percent taken from creatorStake
     * @param _maxRevision maximum allowed revisions
     * @param _CancelByMe reputation penalty points
     * @param _requestCancel reputation penalty points
     * @param _respondCancel reputation penalty points
     * @param _revision reputation penalty points
     * @param _taskAcceptCreator reputation reward points
     * @param _taskAcceptMember reputation reward points
     * @param _deadlineHitCreator reputation penalty points
     * @param _deadlineHitMember reputation penalty points
     */
    function initialize(
        address _employeeAssignment,
        address payable _systemWallet,
        uint64 _cooldownInHour,
        uint32 _maxStake,
        uint32 _NegPenalty,
        uint32 _maxReward,
        uint32 _minRevisionTimeInHour,
        uint32 _feePercentage,
        uint32 _maxRevision,
        uint32 _CancelByMe,
        uint32 _requestCancel,
        uint32 _respondCancel,
        uint32 _revision,
        uint32 _taskAcceptCreator,
        uint32 _taskAcceptMember,
        uint32 _deadlineHitCreator,
        uint32 _deadlineHitMember
    ) public initializer {
        // validate
        zero_Address(_systemWallet);
        zero_Address(_employeeAssignment);

        // init parents
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        // set employeeAssignment (AccesControl expects this)
        employeeAssignment = IEmployeeAssignment(_employeeAssignment);

        // system config
        systemWallet = _systemWallet;
        algoConstant = 1e3; // conservative default
        taskCounter = 0;
        feeCollected = 0;

        StateVars = StateVar({
            cooldownInHour: _cooldownInHour,
            minRevisionTimeInHour: _minRevisionTimeInHour,
            NegPenalty: _NegPenalty,
            maxReward: _maxReward,
            feePercentage: _feePercentage,
            maxStake: _maxStake,
            maxRevision: _maxRevision
        });

        reputationPoints = reputationPoint({
            CancelByMe: _CancelByMe,
            requestCancel: _requestCancel,
            respondCancel: _respondCancel,
            revision: _revision,
            taskAcceptCreator: _taskAcceptCreator,
            taskAcceptMember: _taskAcceptMember,
            deadlineHitCreator: _deadlineHitCreator,
            deadlineHitMember: _deadlineHitMember
        });
    }

//  // =============================================================
    // USER MANAGEMENT
    // =============================================================

    /**
     * @notice Register the caller as a user.
     * @param Name display name
     * @param Age age
     * @dev Requires caller to be non-employee (onlyUser) and non-zero caller.
     */
    function register(string calldata Name, uint8 Age)
        external
        onlyUser
        callerZeroAddr
    {
        User storage u = Users[msg.sender];
        if (u.isRegistered) revert AlredyRegistered();
        if (bytes(Name).length == 0) revert InvalidName();
        if (Age < 18) revert InvalidAge();
        if(Age > 100) revert InvalidAge();

        u.reputation = 0;
        u.totalTasksCompleted = 0;
        u.totalTasksFailed = 0;
        u.isRegistered = true;
        u.name = Name;
        u.age = Age;

        emit UserRegistered(msg.sender, Name, Age);
    }

    /**
     * @notice Unregister caller and delete stored user data.
     * @return confirmation string
     */
    function Unregister()
        external
        onlyRegistered
        onlyUser
        callerZeroAddr
        returns (string memory)
    {
        User memory u = Users[msg.sender];
        emit UserUnregistered(msg.sender, u.name, u.age);
        delete Users[msg.sender];
        return "Unregister Successfully";
    }

    /**
     * @notice Get caller's stored user data
     */
    function getMyData() external view onlyRegistered returns (User memory) {
        return Users[msg.sender];
    }
//
//  // =============================================================
    // INTERNAL HELPERS
    // =============================================================

    /**
     * @notice Read stored reputation for a given address
     * @dev Fallback to myPoint mapping if Users entry not present (backwards compatibility)
     */
    function _seeReputation(address who) internal view returns (uint32) {
        if (Users[who].isRegistered) {
            return Users[who].reputation;
        } else {
            return 0;
        }
    }

    /**
     * @notice Counter for penalty complement (100 - NegPenalty)
     */
    function _CounterPenalty() internal view returns (uint32) {
        StateVar storage sv = StateVars;
        return uint32(100) - sv.NegPenalty;
    }

    /**
     * @notice Reset cancel request slot for a task
     */
    function _resetCancelRequest(uint256 taskId) internal {
        CancelRequest storage cr = CancelRequests[taskId];
        cr.requester = address(0);
        cr.counterparty = address(0);
        cr.expiry = 0;
        cr.status = TaskRejectRequest.None;
        cr.reason = "";
    }

    // =============================================================
    // STAKE CALCULATIONS
    // =============================================================

    /**
     * @notice Calculate member stake required for a task for an applicant
     * @param taskId id of task
     * @param applicant address of applicant
     * @return memberStake calculated in wei
     */
    function getMemberRequiredStakeFor(uint256 taskId, address applicant) public view returns (uint256) {
        Task storage t = Tasks[taskId];
        uint256 hoursInput = uint256(t.deadlineHours);
        // formula: reward * (hours+1) * algo / ((repApplicant+1)*(repCreator+1)*(maxRevision+1))
        // uses reward in wei
        uint256 memberStake = (t.reward * (hoursInput + 1) * algoConstant) /
            (uint256(_seeReputation(applicant) + 1) * uint256(_seeReputation(t.creator) + 1) * uint256(t.maxRevision + 1));
        return memberStake;
    }

    /**
     * @notice Calculate creator stake required (explicit)
     * @param creator creator address (for reputation)
     * @param rewardWei reward in wei
     * @param maxRevision allowed revisions
     * @param deadlineHours configured hours
     * @return creatorStake in wei
     */
    function getCreatorRequiredStakeFor(
        address creator,
        uint256 rewardWei,
        uint8 maxRevision,
        uint256 deadlineHours
    ) public view returns (uint256) {
        uint256 creatorStake = (rewardWei * (uint256(maxRevision) + 1) * algoConstant) /
            (uint256(_seeReputation(creator) + 1) * (deadlineHours + 1));
        return creatorStake;
    }

    /**
     * @notice Backwards-compatible wrapper using msg.sender as applicant
     */
    function getMemberRequiredStake(uint256 taskId) public view returns (uint256) {
        return getMemberRequiredStakeFor(taskId, msg.sender);
    }
//
    // =============================================================
    // TASK LIFECYCLE
    // =============================================================

    /**
     * @notice Create a new task and fund reward + creator stake + fee via msg.value
     * @param Title task title
     * @param GithubURL task reference url
     * @param _DeadlineHours configured deadline in hours (used when member accepted)
     * @param maximumRevision allowed number of revisions
     * @param RewardEther reward amount in ETH (uint representing whole Ethers)
     *
     * @dev msg.value must equal (_rewardWei + creatorStake + fee)
     */
    function createTask(
        string memory Title,
        string memory GithubURL,
        uint32 _DeadlineHours,
        uint8 maximumRevision,
        uint256 RewardEther
    ) external payable whenNotPaused onlyRegistered onlyUser callerZeroAddr {
        StateVar storage sv = StateVars;
        // increment task id first (1-indexed)
        taskCounter++;
        uint256 taskId = taskCounter;

        // reward in wei
        uint256 _reward = RewardEther * 1 ether;

        // validations
        if (bytes(Title).length == 0) revert InvalidTitle();
        if (bytes(GithubURL).length == 0) revert InvalidGithubURL();
        if (_DeadlineHours < sv.minRevisionTimeInHour) revert InvalidDeadline();
        if (maximumRevision > sv.maxRevision) revert TooManyRevisions();
        if (RewardEther == 0) revert InvalidRewardAmount();
        if (RewardEther > sv.maxReward) revert InvalidRewardAmount();

        // compute creator stake
        uint256 creatorStake = getCreatorRequiredStakeFor(msg.sender, _reward, maximumRevision, _DeadlineHours);
        if (sv.maxStake < creatorStake) revert StakeHitLimit();

        // fee (protocol) taken from creatorStake (business decision)
        uint256 fee = (creatorStake * sv.feePercentage) / 100;
        feeCollected += fee;

        // total expected from msg.value
        uint256 total = _reward + creatorStake + fee;
        if (msg.value != total) revert InsufficientStake();

        // store task (deadlineAt = 0 until member accepted)
        Tasks[taskId] = Task({
            taskId: taskId,
            status: TaskStatus.Active,
            creator: msg.sender,
            member: address(0),
            title: Title,
            githubURL: GithubURL,
            reward: _reward,
            deadlineHours: _DeadlineHours,
            deadlineAt: 0,
            createdAt: block.timestamp,
            creatorStake: creatorStake,
            memberStake: 0,
            maxRevision: maximumRevision,
            isMemberStakeLocked: false,
            isCreatorStakeLocked: true,
            isRewardClaimed: false,
            exists: true
        });

        // counters
        Users[msg.sender].totalTasksCreated++;

        emit TaskCreated(Title, taskId, msg.sender, _reward, creatorStake);
    }

    /**
     * @notice Open registration for applicants (only creator)
     */
    function openRegistration(uint256 taskId) external taskExists(taskId) onlyTaskCreator(taskId) whenNotPaused {
        Task storage t = Tasks[taskId];
        require(t.status == TaskStatus.Active, "not active");
        t.status = TaskStatus.OpenRegistration;
        emit RegistrationOpened(taskId);
    }

    /**
     * @notice Close registration (only creator)
     */
    function closeRegistration(uint256 taskId) external taskExists(taskId) onlyTaskCreator(taskId) whenNotPaused {
        Task storage t = Tasks[taskId];
        require(t.status == TaskStatus.OpenRegistration, "not open");
        t.status = TaskStatus.Active;
        emit RegistrationClosed(taskId);
    }

    /**
     * @notice Applicant requests to join by staking the required amount
     * @dev msg.value must equal required member stake for applicant
     */
    function requestJoinTask(uint256 taskId) external payable taskExists(taskId) whenNotPaused onlyRegistered onlyUser callerZeroAddr {
        StateVar storage sv = StateVars;
        Task storage t = Tasks[taskId];
        JoinRequest[] storage reqs = joinRequests[taskId];

        // prevent duplicate pending request
        for (uint256 i = 0; i < reqs.length; ++i) {
            if (reqs[i].applicant == msg.sender && reqs[i].isPending) revert AlreadyRequestedJoin();
        }

        if (t.status != TaskStatus.OpenRegistration) revert TaskNotOpen();
        if (msg.sender == t.creator) revert TaskNotOpen();

        // compute stake
        uint256 memberStake = getMemberRequiredStakeFor(taskId, msg.sender);
        if (sv.maxStake < memberStake) revert StakeHitLimit();
        if (msg.value != memberStake) revert InsufficientStake();

        // push request
        joinRequests[taskId].push(JoinRequest({
            applicant: msg.sender,
            stakeAmount: msg.value,
            status: UserTask.Request,
            isPending: true,
            hasWithdrawn: false
        }));

        emit JoinRequested(taskId, msg.sender, msg.value);
    }

    /**
     * @notice Creator approves a join request. This locks the member stake and starts the task deadline timer.
     */
    function approveJoinRequest(uint256 taskId, address _applicant) external taskExists(taskId) onlyTaskCreator(taskId) nonReentrant whenNotPaused {
        JoinRequest[] storage requests = joinRequests[taskId];
        Task storage t = Tasks[taskId];
        bool found = false;

        for (uint256 i = 0; i < requests.length; ++i) {
            if (requests[i].applicant == _applicant && requests[i].isPending) {
                requests[i].isPending = false;
                requests[i].status = UserTask.Accepted;
                t.member = _applicant;
                t.memberStake = requests[i].stakeAmount;
                t.isMemberStakeLocked = true;
                found = true;
                break;
            }
        }
        require(found, "request not found");

        // set deadline timestamp based on stored hours
        t.deadlineAt = block.timestamp + (uint256(t.deadlineHours) * 1 hours);
        t.status = TaskStatus.InProgres;

        emit JoinApproved(taskId, _applicant);
    }

    /**
     * @notice Creator rejects a join request. Applicant stake is credited to withdrawable.
     */
    function rejectJoinRequest(uint256 taskId, address _applicant) external taskExists(taskId) onlyTaskCreator(taskId) nonReentrant whenNotPaused {
        JoinRequest[] storage requests = joinRequests[taskId];
        bool found = false;

        for (uint256 i = 0; i < requests.length; ++i) {
            if (requests[i].applicant == _applicant && requests[i].isPending) {
                requests[i].isPending = false;
                uint256 stake = requests[i].stakeAmount;
                requests[i].stakeAmount = 0;
                requests[i].hasWithdrawn = true;
                withdrawable[_applicant] += stake;
                found = true;
                break;
            }
        }
        require(found, "request not found");
        emit JoinRejected(taskId, _applicant);
    }

    // =============================================================
    // CANCEL / NEGOTIATION
    // =============================================================

    /**
     * @notice Request a cancellation negotiation (only creator or member)
     * @param taskId target task
     * @param reason textual reason
     */
    function requestCancel(uint256 taskId, string calldata reason) external whenNotPaused onlyRegistered onlyUser taskExists(taskId) {
        StateVar storage sv = StateVars;
        Task storage t = Tasks[taskId];
        CancelRequest storage cr = CancelRequests[taskId];
        reputationPoint storage rp = reputationPoints;

        if (cr.status == TaskRejectRequest.Pending) revert CancelAlreadyRequested();
        if (msg.sender != t.creator && msg.sender != t.member) revert NotTaskMember();
        if (t.member == address(0)) revert CancelOnlyWhenMemberAssigned();
        if (bytes(reason).length == 0) revert InvalidReason();

        address counterparty = (msg.sender == t.creator) ? t.member : t.creator;
        cr.requester = msg.sender;
        cr.counterparty = counterparty;
        cr.expiry = block.timestamp + (sv.cooldownInHour * 1 hours);
        cr.status = TaskRejectRequest.Pending;
        cr.reason = reason;
        t.status = TaskStatus.CancelRequested;

        // penalize requester reputation points
        if (Users[msg.sender].isRegistered) {
            if (Users[msg.sender].reputation < rp.requestCancel) Users[msg.sender].reputation = 0;
            else Users[msg.sender].reputation -= rp.requestCancel;
        }
        emit CancelRequestedEvent(taskId, msg.sender, reason, (sv.cooldownInHour * 1 hours));
    }

    /**
     * @notice Counterparty responds to cancel request
     * @param taskId target task
     * @param approve whether to approve cancel
     */
    function respondCancel(uint256 taskId, bool approve) external taskExists(taskId) nonReentrant onlyUser onlyRegistered whenNotPaused {
        Task storage t = Tasks[taskId];
        CancelRequest storage cr = CancelRequests[taskId];
        reputationPoint storage rp = reputationPoints;

        if (cr.status != TaskRejectRequest.Pending) revert NoActiveCancelRequest();
        if (msg.sender != cr.counterparty) revert NotCounterparty();
        if (t.member == address(0)) revert CancelOnlyWhenMemberAssigned();

        // expired negotiation
        if (block.timestamp > cr.expiry) {
            _resetCancelRequest(taskId);
            t.status = TaskStatus.InProgres;
            emit CancelResponded(taskId, false);
            return;
        }

        // not approved: reset state
        if (!approve) {
            _resetCancelRequest(taskId);
            t.status = TaskStatus.InProgres;
            emit CancelResponded(taskId, false);
            return;
        }

        // approved: return funds accordingly
        if (t.member != address(0)) {
            withdrawable[t.creator] += t.creatorStake + t.reward;
            withdrawable[t.member] += t.memberStake;
            t.isMemberStakeLocked = false;
            t.isCreatorStakeLocked = false;
        } else {
            withdrawable[t.creator] += t.creatorStake + t.reward;
            t.isCreatorStakeLocked = false;
        }

        t.status = TaskStatus.Cancelled;
        _resetCancelRequest(taskId);

        // apply reputation penalty to responder (msg.sender)
        if (Users[msg.sender].isRegistered) {
            if (Users[msg.sender].reputation < rp.respondCancel) Users[msg.sender].reputation = 0;
            else Users[msg.sender].reputation -= rp.respondCancel;
        }

        // update counters
        Users[t.creator].totalTasksFailed++;
        if (t.member != address(0)) {
            Users[t.member].totalTasksFailed++;
        }

        emit CancelResponded(taskId, true);
    }

    /**
     * @notice Either party cancels the task immediately (with penalties)
     * @dev Penalty distribution: member cancels => part of memberStake to creator; creator cancels => part of creatorStake to member
     */
    function cancelByMe(uint256 taskId) external taskExists(taskId) nonReentrant onlyUser whenNotPaused {
        StateVar storage sv = StateVars;
        reputationPoint storage rp = reputationPoints;
        Task storage t = Tasks[taskId];

        if (msg.sender != t.creator && msg.sender != t.member) revert NotTaskMember();
        if (CancelRequests[taskId].status == TaskRejectRequest.Pending) revert CancelAlreadyRequested();
        if (t.status != TaskStatus.InProgres) revert TaskNotOpen();

        if (msg.sender == t.member) {
            // member cancels: member loses portion of their stake to creator
            uint256 penaltyToCreator = (t.memberStake * sv.NegPenalty) / 100;
            uint256 memberReturn = (t.memberStake * _CounterPenalty()) / 100;

            // credit amounts
            withdrawable[t.creator] += t.creatorStake + t.reward + penaltyToCreator;
            withdrawable[t.member] += memberReturn;

            // unlock
            t.isMemberStakeLocked = false;
            t.isCreatorStakeLocked = false;
        } else {
            // creator cancels: creator loses portion of creatorStake to member
            if (t.member == address(0)) revert CancelOnlyWhenMemberAssigned();

            uint256 penaltyToMember = (t.creatorStake * sv.NegPenalty) / 100;
            uint256 creatorReturn = (t.creatorStake * _CounterPenalty()) / 100 + t.reward;

            withdrawable[t.member] += t.memberStake + penaltyToMember;
            withdrawable[t.creator] += creatorReturn;

            t.isMemberStakeLocked = false;
            t.isCreatorStakeLocked = false;
        }

        t.status = TaskStatus.Cancelled;

        // apply reputation penalty to initiator
        if (Users[msg.sender].isRegistered) {
            if (Users[msg.sender].reputation < rp.CancelByMe) Users[msg.sender].reputation = 0;
            else Users[msg.sender].reputation -= rp.CancelByMe;
        }

        // update counters
        Users[msg.sender].totalTasksFailed++;

        emit TaskCancelledByMe(taskId, msg.sender);
    }

    // =============================================================
    // SUBMISSION / APPROVAL / REVISION
    // =============================================================

    /**
     * @notice Member submits pull request (no ether transfer)
     */
    function requestSubmitTask(uint256 taskId, string calldata PullRequestURL, string calldata Note)
        external
        onlyTaskMember(taskId)
        taskExists(taskId)
        whenNotPaused
        onlyUser
    {
        Task storage t = Tasks[taskId];
        if (t.status != TaskStatus.InProgres) revert TaskNotOpen();
        if (t.member != msg.sender) revert NotTaskMember();
        if (bytes(PullRequestURL).length == 0) revert InvalidGithubURL();
        if (bytes(Note).length == 0) revert InvalidNote();

        TaskSubmits[taskId] = TaskSubmit({
            githubURL: PullRequestURL,
            sender: msg.sender,
            note: Note,
            status: SubmitStatus.Pending,
            revisionTime: 0,
            newDeadline: t.deadlineAt
        });

        emit TaskSubmitted(taskId, msg.sender, PullRequestURL);
    }

    /**
     * @notice Member re-submits after revision requested
     */
    function reSubmitTask(uint256 taskId, string calldata Note, string calldata GithubFixedURL)
        external
        onlyTaskMember(taskId)
        taskExists(taskId)
        whenNotPaused
        onlyUser
    {
        Task storage t = Tasks[taskId];
        TaskSubmit storage s = TaskSubmits[taskId];

        if (t.member != msg.sender) revert NotTaskMember();
        if (s.status != SubmitStatus.RevisionNeeded) revert TaskNotOpen();
        if (s.revisionTime > t.maxRevision) {
        approveTask(taskId);
        return;
        }
        require(s.sender != address(0), "no submission");
        if (bytes(GithubFixedURL).length == 0) revert InvalidGithubURL();
        if (bytes(Note).length == 0) revert InvalidNote();

        s.note = Note;
        s.status = SubmitStatus.Pending;
        s.githubURL = GithubFixedURL;

        if (s.revisionTime > t.maxRevision) {
            // auto-approve if revision exceeded limit
            approveTask(taskId);
            return;
        }

        emit TaskReSubmitted(taskId, msg.sender);
    }

    /**
     * @notice Creator approves submission, triggering payout allocations (pull model)
     */
    function approveTask(uint256 taskId)
        public
        taskExists(taskId)
        onlyTaskCreator(taskId)
        nonReentrant
        whenNotPaused
    {
        reputationPoint storage rp = reputationPoints;
        Task storage t = Tasks[taskId];
        TaskSubmit storage s = TaskSubmits[taskId];

        if (t.status != TaskStatus.InProgres) revert TaskNotOpen();
        if (s.status != SubmitStatus.Pending) revert TaskNotSubmittedYet();
        require(!t.isRewardClaimed, "already claimed");
        require(s.sender != address(0), "no submission");

        uint256 memberGet = t.reward + t.memberStake;
        uint256 creatorGet = t.creatorStake;

        // credit withdrawable balances (pull model)
        withdrawable[t.member] += memberGet;
        withdrawable[t.creator] += creatorGet;

        // unlock stakes and mark claimed
        t.isMemberStakeLocked = false;
        t.isCreatorStakeLocked = false;
        t.isRewardClaimed = true;
        t.status = TaskStatus.Completed;

        // reputations updates
        if (Users[t.member].isRegistered) Users[t.member].reputation += rp.taskAcceptMember;

        if (Users[t.creator].isRegistered) Users[t.creator].reputation += rp.taskAcceptCreator;

        // counters
        Users[t.creator].totalTasksCompleted++;
        Users[t.member].totalTasksCompleted++;

        // clear submission slot
        s.githubURL = "";
        s.sender = address(0);
        s.note = "";
        s.status = SubmitStatus.Accepted;
        s.revisionTime = 0;
        s.newDeadline = 0;

        emit TaskApproved(taskId);
    }

    /**
     * @notice Creator requests revision for a submission
     * @param additionalDeadlineHours how many hours to extend from now
     */
    function requestRevision(uint256 taskId, string calldata Note, uint256 additionalDeadlineHours)
        external
        taskExists(taskId)
        onlyTaskCreator(taskId)
        whenNotPaused
    {
        StateVar storage sv = StateVars;
        Task storage t = Tasks[taskId];
        TaskSubmit storage s = TaskSubmits[taskId];
        reputationPoint storage rp = reputationPoints;

        if (t.member == address(0)) revert CancelOnlyWhenMemberAssigned();
        require(s.status == SubmitStatus.Pending, "not pending");
        require(additionalDeadlineHours >= sv.minRevisionTimeInHour, "please give more time");

        uint256 additionalSeconds = (additionalDeadlineHours * 1 hours);

        s.status = SubmitStatus.RevisionNeeded;
        s.note = Note;
        s.revisionTime++;
        t.deadlineAt = block.timestamp + additionalSeconds;

        if (s.revisionTime > t.maxRevision) {
            // too many revisions => auto approve
            approveTask(taskId);
            return;
        }

        // penalize both parties slightly for revisions (business rule)
        if (Users[t.member].isRegistered) {
            if (Users[t.member].reputation < rp.revision) Users[t.member].reputation = 0;
            else Users[t.member].reputation -= rp.revision;
        }
        if (Users[t.creator].isRegistered) {
            if (Users[t.creator].reputation < rp.revision) Users[t.creator].reputation = 0;
            else Users[t.creator].reputation -= rp.revision;
        }

        emit RevisionRequested(taskId, s.revisionTime, t.deadlineAt);
    }

    // =============================================================
    // DEADLINE / TIMEOUT HANDLING
    // =============================================================

    /**
     * @notice Trigger task deadline logic. Can be called by anyone.
     * @dev Distributes stakes depending on whether the member submitted on time.
     */
    function triggerDeadline(uint256 taskId) public taskExists(taskId) whenNotPaused {
        StateVar storage sv = StateVars;
        Task storage t = Tasks[taskId];
        reputationPoint storage rp = reputationPoints;

        if (t.status != TaskStatus.InProgres) revert TaskNotOpen();
        if (t.deadlineAt == 0) return;
        if (block.timestamp < t.deadlineAt) return;

        // if member exists and stake present, split memberStake according to NegPenalty
        if (t.member != address(0) && t.memberStake > 0) {
            uint256 toMember = (t.memberStake * sv.NegPenalty) / 100;
            uint256 toCreator = (t.memberStake * _CounterPenalty()) / 100;

            withdrawable[t.member] += toMember;
            withdrawable[t.creator] += toCreator + t.creatorStake + t.reward;

            // unlock both stakes
            t.isMemberStakeLocked = false;
            t.isCreatorStakeLocked = false;
        } else {
            // no member => return creator stake + reward
            withdrawable[t.creator] += t.creatorStake + t.reward;

            // unlock both stakes
            t.isMemberStakeLocked = false;
            t.isCreatorStakeLocked = false;
        }

        // reputation penalties
        if (Users[t.member].isRegistered) {
            if (Users[t.member].reputation < rp.deadlineHitMember) Users[t.member].reputation = 0;
            else Users[t.member].reputation -= rp.deadlineHitMember;
        }

        if (Users[t.creator].isRegistered) {
            if (Users[t.creator].reputation < rp.deadlineHitCreator) Users[t.creator].reputation = 0;
            else Users[t.creator].reputation -= rp.deadlineHitCreator;
        }
        t.status = TaskStatus.Cancelled;

        // counters
        Users[t.creator].totalTasksFailed++;
        if (t.member != address(0)) {
            Users[t.member].totalTasksFailed++;
        }

        emit DeadlineTriggered(taskId);
    }

    // =============================================================
    // PAYMENTS (PULL)
    // =============================================================

    /**
     * @notice Withdraw available balance (pull).
     */
    function withdraw() external nonReentrant onlyRegistered onlyUser whenNotPaused {
        uint256 amount = withdrawable[msg.sender];
        require(amount > 0, "no funds");
        // set state before external call
        withdrawable[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "withdraw failed");
        emit Withdrawal(msg.sender, amount);
    }

    /**
     * @notice Get caller withdrawable amount
     */
    function getWithdrawableAmount() external view onlyRegistered returns (uint256) {
        return withdrawable[msg.sender];
    }

    // =============================================================
    // SYSTEM / ADMIN FUNCTIONS (employees & owner)
    // =============================================================

    /**
     * @notice Set algorithm scaling constant used in stake formulas.
     */
    function setAlgoConstant(uint256 newAlgoConstant) external onlyEmployes whenNotPaused {
        require(newAlgoConstant > 0, "can't be 0");
        algoConstant = newAlgoConstant;
        emit AlgoConstantChanged(newAlgoConstant);
    }

    /**
     * @notice Withdraw accumulated fees to system wallet (manual by employee).
     */
    function withdrawToSystemWallet() external onlyEmployes nonReentrant whenNotPaused {
        uint256 amount = feeCollected;
        require(amount > 0, "no fees");
        feeCollected = 0;
        (bool ok, ) = systemWallet.call{value: amount}("");
        require(ok, "withdraw failed");
        emit FeeWithdrawnToSystemWallet(amount);
    }

    /**
     * @notice Change system wallet address (employees only).
     */
    function changeSystemwallet(address payable _NewsystemWallet) external onlyEmployes whenNotPaused {
        zero_Address(_NewsystemWallet);
        systemWallet = _NewsystemWallet;
        emit SystemWalletChanged(_NewsystemWallet);
    }

    /**
     * @notice Set cooldown hours for cancel negotiation.
     */
    function setCooldownHour(uint64 newCooldown) external onlyEmployes whenNotPaused {
        require(newCooldown > 0, "can't be 0");
        StateVars.cooldownInHour = newCooldown;
        emit CooldownChanged(newCooldown);
    }

    /**
     * @notice Set max stake allowed.
     */
    function setMaxStake(uint32 newMaxStake) external onlyEmployes whenNotPaused {
        require(newMaxStake > 0, "can't be 0");
        StateVars.maxStake = newMaxStake;
        emit MaxStakeChanged(newMaxStake);
    }

    /**
     * @notice Set negative penalty percent (0..100)
     */
    function setNegativePenalty(uint32 newNegPenalty) external onlyEmployes whenNotPaused {
        require(newNegPenalty <= 100, "neg penalty must be <= 100");
        require(newNegPenalty > 0,"neg penalty can't be 0");
        StateVars.NegPenalty = newNegPenalty;
    }

    /**
     * @notice Set minimum revision time in hours
     */
    function setMinRevisionTimeInHour(uint32 _minRevisionTimeInHour) external onlyEmployes whenNotPaused {
        StateVars.minRevisionTimeInHour = _minRevisionTimeInHour;
    }

    /**
     * @notice Set fee percentage applied to creatorStake
     */
    function setfeePercentage(uint32 newfeePercentage) external onlyEmployes whenNotPaused {
        StateVars.feePercentage = newfeePercentage;
    }

    /**
     * @notice Set maximum reward (input unit = ether)
     */
    function setMaxReward(uint32 _maxReward) external onlyEmployes whenNotPaused {
        StateVars.maxReward = _maxReward;
    }

    /**
     * @notice Set reputation penalty/award points in one call
     */
    function setPenaltyPoint(
        uint32 newCancelByMe,
        uint32 newrequestCancel,
        uint32 newrespondCancel,
        uint32 newrevision,
        uint32 newtaskAcceptCreator,
        uint32 newtaskAcceptMember,
        uint32 newdeadlineHitCreator,
        uint32 newdeadlineHitMember
    ) external onlyEmployes whenNotPaused {
        reputationPoints.CancelByMe = newCancelByMe;
        reputationPoints.requestCancel = newrequestCancel;
        reputationPoints.respondCancel = newrespondCancel;
        reputationPoints.revision = newrevision;
        reputationPoints.taskAcceptCreator = newtaskAcceptCreator;
        reputationPoints.taskAcceptMember = newtaskAcceptMember;
        reputationPoints.deadlineHitCreator = newdeadlineHitCreator;
        reputationPoints.deadlineHitMember = newdeadlineHitMember;
    }

    function pause() external onlyEmployes {
    _pause();
    emit ContractPaused(msg.sender);
    }
    function unpause() external onlyEmployes {
    _unpause();
    emit ContractUnpaused(msg.sender);
    }

    // =============================================================
    // READ HELPERS
    // =============================================================

    function getJoinRequests(uint256 taskId) external view onlyRegistered returns (JoinRequest[] memory) {
        return joinRequests[taskId];
    }

    function getTaskSubmit(uint256 taskId) external view onlyRegistered returns (TaskSubmit memory) {
        return TaskSubmits[taskId];
    }

    // =============================================================
    // FALLBACKS
    // =============================================================

    receive() external payable {
        revert();
    }

    fallback() external payable {
        revert();
    }

    // =============================================================
    // UPGRADE AUTH
    // =============================================================

    /**
     * @notice Authorize UUPS upgrades. Only owner (as provided by AccesControl) can upgrade.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner whenNotPaused {}

}
