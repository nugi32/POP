// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Pipe/StateVarPipes.sol";
import "../Pipe/AccesControlPipes.sol";
import "../system/utils/StakeUtils.sol";
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
 *  - Fee (protocol share) stored in `feeCollected` and withdrawn manuall by employees.
 */
contract TrustlessTeamProtocol is
    Initializable,
    AccesControl,
    stakeUtils,
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
//
    // =============================================================
    // STRUCTS
    // =============================================================

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

    /// @notice Core task data
    struct Task {
        uint256 taskId;
        TaskStatus status;
        TaskValue value;
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

    uint256 public taskCounter;
    uint256 internal feeCollected;
    uint256 public memberStakePercentReward;
    address payable public systemWallet;

    // Storage gap for upgradeability
    uint256[40] private ___gap;

//
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
    event memberStakePercentRewardChanged(uint256 NewmemberStakePercentReward);
    event SystemWalletChanged(address newWallet);
    event FeeWithdrawnToSystemWallet(uint256 amount);
    event ContractPaused(address indexed caller);
    event ContractUnpaused(address indexed caller);
    event AccessControlChanged(address newAccessControl);
    event StateVarChanged(address newStateVar);

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
    error RewardOverflow();
    error ValueMismatch();
    error StakeOverflow();
    error StakeMismatch();
    error NoSubmision();

    //system
    error InvalidMaxStakeAmount();
    error TotalMustBe10();

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


    function initialize(
        address _accessControl,
        address payable _systemWallet,
        address _stateVar,
        uint256 _initialmemberStakePercentReward
    ) public initializer {
        // validate
        zero_Address(_systemWallet);
        zero_Address(_accessControl);
        zero_Address(_stateVar);

        // init parents
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        // set employeeAssignment (AccesControl expects this)
        accessControl = IAccessControl(_accessControl);
        stateVarUtils_init(_stateVar);

        // system config
        systemWallet = _systemWallet;
        taskCounter = 0;
        feeCollected = 0;
        memberStakePercentReward = _initialmemberStakePercentReward;
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
    function Register(string calldata Name, uint8 Age)
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
//
    // =============================================================
    // TASK LIFECYCLE
    // =============================================================


    function createTask(
        string memory Title,
        string memory GithubURL,
        uint32 DeadlineHours,
        uint8 MaximumRevision,
        uint256 RewardEther,
        uint256 CreatorStakeEther
        //,uint256 creatorStake
    ) external payable whenNotPaused onlyRegistered onlyUser callerZeroAddr {
        // increment task id first (1-indexed)
        taskCounter++;
        uint256 taskId = taskCounter;

        // reward in ether
        uint256 _reward = RewardEther * 1 ether;
        if (_reward / 1 ether != RewardEther) revert RewardOverflow();

        uint256 _CreatorStake = getCreatorStake(DeadlineHours, MaximumRevision, _reward);

        uint256 _stake = CreatorStakeEther * 1 ether;
        if (_stake / 1 ether != CreatorStakeEther) revert StakeOverflow();
        if (_stake != _CreatorStake) revert StakeMismatch();

        // validations
        if (bytes(Title).length == 0) revert InvalidTitle();
        if (bytes(GithubURL).length == 0) revert InvalidGithubURL();
        if (___getMinRevisionTimeInHour() < DeadlineHours) revert InvalidDeadline();
        if (___getMaxRevision() < MaximumRevision) revert TooManyRevisions();
        if (RewardEther == 0) revert InvalidRewardAmount();
        if (RewardEther > ___getMaxReward()) revert InvalidRewardAmount();
        if (___getMaxStake() < _CreatorStake) revert StakeHitLimit();

        // fee (protocol) taken from creatorStake (business decision)
        // fee (protocol) taken from creatorStake (business decision)
        uint256 totalFee = (_CreatorStake * ___getFeePercentage()) / 100;
        //if (__creatorStake != creatorStake) revert ValueMismatch();
        uint256 creatorStakeNet = _CreatorStake - totalFee;

        feeCollected += totalFee;

        uint256 totalRequired = _reward + creatorStakeNet;
        if (msg.value != totalRequired) revert InsufficientStake();


        // store task (deadlineAt = 0 until member accepted)
        Tasks[taskId] = Task({
            taskId: taskId,
            status: TaskStatus.Active,
            value: ___getProjectValueCategory(__getProjectValueNum(DeadlineHours, MaximumRevision, RewardEther, msg.sender)),
            creator: msg.sender,
            member: address(0),
            title: Title,
            githubURL: GithubURL,
            reward: _reward,
            deadlineHours: DeadlineHours,
            deadlineAt: 0,
            createdAt: block.timestamp,
            creatorStake: creatorStakeNet,
            memberStake: 0,
            maxRevision: MaximumRevision,
            isMemberStakeLocked: false,
            isCreatorStakeLocked: true,
            isRewardClaimed: false,
            exists: true
        });

        // counters
        Users[msg.sender].totalTasksCreated++;

        emit TaskCreated(Title, taskId, msg.sender, _reward, creatorStakeNet);
    }

    /**
     * @notice Open registration for applicants (only creator)
     */
    function openRegistration(uint256 taskId) external taskExists(taskId) onlyTaskCreator(taskId) whenNotPaused {
        Task storage t = Tasks[taskId];
        if (t.status != TaskStatus.Active) revert TaskNotOpen();
        t.status = TaskStatus.OpenRegistration;
        emit RegistrationOpened(taskId);
    }

    /**
     * @notice Close registration (only creator)
     */
    function closeRegistration(uint256 taskId) external taskExists(taskId) onlyTaskCreator(taskId) whenNotPaused {
        Task storage t = Tasks[taskId];
        if (t.status != TaskStatus.OpenRegistration) revert TaskNotOpen();
        t.status = TaskStatus.Active;
        emit RegistrationClosed(taskId);
    }

    /**
     * @notice Applicant requests to join by staking the required amount
     * @dev msg.value must equal required member stake for applicant
     */
    function requestJoinTask(uint256 taskId) external payable taskExists(taskId) whenNotPaused onlyRegistered onlyUser callerZeroAddr {
        Task storage t = Tasks[taskId];
        JoinRequest[] storage reqs = joinRequests[taskId];

        // prevent duplicate pending request
        for (uint256 i = 0; i < reqs.length; ++i) {
            if (reqs[i].applicant == msg.sender && reqs[i].isPending) revert AlreadyRequestedJoin();
        }

        if (t.status != TaskStatus.OpenRegistration) revert TaskNotOpen();
        if (msg.sender == t.creator) revert TaskNotOpen();

        // compute stake
        uint256 memberStake = getMemberRequiredStake(taskId);
        if (___getMaxStake() < memberStake) revert StakeHitLimit();
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
//
    // =============================================================
    // CANCEL / NEGOTIATION
    // =============================================================

    /**
     * @notice Request a cancellation negotiation (only creator or member)
     * @param taskId target task
     * @param reason textual reason
     */
    function requestCancel(uint256 taskId, string calldata reason) external whenNotPaused onlyRegistered onlyUser taskExists(taskId) {
        Task storage t = Tasks[taskId];
        CancelRequest storage cr = CancelRequests[taskId];

        if (cr.status == TaskRejectRequest.Pending) revert CancelAlreadyRequested();
        if (msg.sender != t.creator && msg.sender != t.member) revert NotTaskMember();
        if (t.member == address(0)) revert CancelOnlyWhenMemberAssigned();
        if (bytes(reason).length == 0) revert InvalidReason();

        address counterparty = (msg.sender == t.creator) ? t.member : t.creator;
        cr.requester = msg.sender;
        cr.counterparty = counterparty;
        cr.expiry = block.timestamp + (___getCooldownInHour() * 1 hours);
        cr.status = TaskRejectRequest.Pending;
        cr.reason = reason;
        t.status = TaskStatus.CancelRequested;

        // penalize requester reputation points
        if (Users[msg.sender].isRegistered) {
            if (Users[msg.sender].reputation < ___getRequestCancel()) Users[msg.sender].reputation = 0;
            else Users[msg.sender].reputation -= ___getRequestCancel();
        }
        emit CancelRequestedEvent(taskId, msg.sender, reason, (___getCooldownInHour() * 1 hours));
    }

    /**
     * @notice Counterparty responds to cancel request
     * @param taskId target task
     * @param approve whether to approve cancel
     */
    function respondCancel(uint256 taskId, bool approve) external taskExists(taskId) nonReentrant onlyUser onlyRegistered whenNotPaused {
        Task storage t = Tasks[taskId];
        CancelRequest storage cr = CancelRequests[taskId];

        if (cr.status != TaskRejectRequest.Pending) revert NoActiveCancelRequest();
        if (msg.sender != cr.counterparty) revert NotCounterparty();
        if (t.member == address(0)) revert CancelOnlyWhenMemberAssigned();

        // expired negotiation
        if (block.timestamp > cr.expiry) {
            __resetCancelRequest(taskId);
            t.status = TaskStatus.InProgres;
            emit CancelResponded(taskId, false);
            return;
        }

        // not approved: reset state
        if (!approve) {
            __resetCancelRequest(taskId);
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
        __resetCancelRequest(taskId);

        // apply reputation penalty to responder (msg.sender)
        if (Users[msg.sender].isRegistered) {
            if (Users[msg.sender].reputation < ___getRespondCancel()) Users[msg.sender].reputation = 0;
            else Users[msg.sender].reputation -= ___getRespondCancel();
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
        Task storage t = Tasks[taskId];

        if (msg.sender != t.creator && msg.sender != t.member) revert NotTaskMember();
        if (CancelRequests[taskId].status == TaskRejectRequest.Pending) revert CancelAlreadyRequested();
        if (t.status != TaskStatus.InProgres) revert TaskNotOpen();

        if (msg.sender == t.member) {
            // member cancels: member loses portion of their stake to creator
            uint256 penaltyToCreator = (t.memberStake * ___getNegPenalty()) / 100;
            uint256 memberReturn = (t.memberStake * __CounterPenalty()) / 100;

            // credit amounts
            withdrawable[t.creator] += t.creatorStake + t.reward + penaltyToCreator;
            withdrawable[t.member] += memberReturn;

            // unlock
            t.isMemberStakeLocked = false;
            t.isCreatorStakeLocked = false;
        } else {
            // creator cancels: creator loses portion of creatorStake to member
            if (t.member == address(0)) revert CancelOnlyWhenMemberAssigned();

            uint256 penaltyToMember = (t.creatorStake * ___getNegPenalty()) / 100;
            uint256 creatorReturn = (t.creatorStake * __CounterPenalty()) / 100 + t.reward;

            withdrawable[t.member] += t.memberStake + penaltyToMember;
            withdrawable[t.creator] += creatorReturn;

            t.isMemberStakeLocked = false;
            t.isCreatorStakeLocked = false;
        }

        t.status = TaskStatus.Cancelled;

        // apply reputation penalty to initiator
        if (Users[msg.sender].isRegistered) {
            if (Users[msg.sender].reputation < ___getCancelByMe()) Users[msg.sender].reputation = 0;
            else Users[msg.sender].reputation -= ___getCancelByMe();
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

        if (s.sender == address(0)) revert NoSubmision();  //note !!
        if (t.member != msg.sender) revert NotTaskMember();
        if (s.status != SubmitStatus.RevisionNeeded) revert TaskNotOpen();

        // auto-approve if revision exceeded limit
        if (s.revisionTime > t.maxRevision) {
        __approveTask(taskId);
        return;
        }
        require(s.sender != address(0), "no submission");
        if (bytes(GithubFixedURL).length == 0) revert InvalidGithubURL();
        if (bytes(Note).length == 0) revert InvalidNote();

        s.note = Note;
        s.status = SubmitStatus.Pending;
        s.githubURL = GithubFixedURL;

        emit TaskReSubmitted(taskId, msg.sender);
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
        Task storage t = Tasks[taskId];
        TaskSubmit storage s = TaskSubmits[taskId];

        if (t.member == address(0)) revert CancelOnlyWhenMemberAssigned();
        require(s.status == SubmitStatus.Pending, "not pending");
        require(additionalDeadlineHours >= ___getMinRevisionTimeInHour(), "please give more time");

        uint256 additionalSeconds = (additionalDeadlineHours * 1 hours);

        s.status = SubmitStatus.RevisionNeeded;
        s.note = Note;
        s.revisionTime++;
        t.deadlineAt = block.timestamp + additionalSeconds;

        if (s.revisionTime > t.maxRevision) {
            // too many revisions => auto approve
            __approveTask(taskId);
            return;
        }

        // penalize both parties slightly for revisions (business rule)
        if (Users[t.member].isRegistered) {
            if (Users[t.member].reputation < ___getRevisionPenalty() ) Users[t.member].reputation = 0;
            else Users[t.member].reputation -= ___getRevisionPenalty() ;
        }
        if (Users[t.creator].isRegistered) {
            if (Users[t.creator].reputation < ___getRevisionPenalty() ) Users[t.creator].reputation = 0;
            else Users[t.creator].reputation -= ___getRevisionPenalty() ;
        }

        emit RevisionRequested(taskId, s.revisionTime, t.deadlineAt);
    }

    function approveTask(uint256 taskId)
        external
        taskExists(taskId)
        onlyTaskCreator(taskId)
        nonReentrant
        whenNotPaused
    {
        __approveTask(taskId);
    }

    // =============================================================
    // DEADLINE / TIMEOUT HANDLING
    // =============================================================

    /**
     * @notice Trigger task deadline logic. Can be called by anyone.
     * @dev Distributes stakes depending on whether the member submitted on time.
     */
    function triggerDeadline(uint256 taskId) public taskExists(taskId) whenNotPaused nonReentrant {
        Task storage t = Tasks[taskId];

        if (t.status != TaskStatus.InProgres) revert TaskNotOpen();
        if (t.deadlineAt == 0) return;
        if (block.timestamp < t.deadlineAt) return;

        // if member exists and stake present, split memberStake according to NegPenalty
        if (t.member != address(0) && t.memberStake > 0) {
            uint256 toMember = (t.memberStake * ___getNegPenalty()) / 100;
            uint256 toCreator = (t.memberStake * __CounterPenalty()) / 100;

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
            if (Users[t.member].reputation < ___getDeadlineHitMember()) Users[t.member].reputation = 0;
            else Users[t.member].reputation -= ___getDeadlineHitMember();
        }

        if (Users[t.creator].isRegistered) {
            if (Users[t.creator].reputation < ___getDeadlineHitCreator()) Users[t.creator].reputation = 0;
            else Users[t.creator].reputation -= ___getDeadlineHitCreator();
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

//---------------------------------------------------- INTERNAL & HELPERS -------------------------------------------------------

    // =============================================================
    // READ HELPERS
    // =============================================================

    /**
     * @notice Get caller's stored user data
     */
    function getMyData() external view onlyRegistered returns (User memory) {
        return Users[msg.sender];
    }

    function getJoinRequests(uint256 taskId) external view onlyRegistered returns (JoinRequest[] memory) {
        return joinRequests[taskId];
    }

    function getTaskSubmit(uint256 taskId) external view onlyRegistered returns (TaskSubmit memory) {
        return TaskSubmits[taskId];
    }

    /**
     * @notice Get caller withdrawable amount
     */
    function getWithdrawableAmount() external view onlyRegistered returns (uint256) {
        return withdrawable[msg.sender];
    }

    function __getProjectValueNum(
    uint32 DeadlineHours,
    uint8 MaximumRevision,
    uint256 rewardWei,
    address Caller
    ) internal view returns (uint256) {
        uint256 rewardEtherUnits = rewardWei / 1 ether;
        uint256 _Value = ((___getRewardScore() / 10) * rewardEtherUnits) + ((___getReputationScore() / 10) * __seeReputation(Caller)) + 
                    ((___getDeadlineScore() / 10) * DeadlineHours) + ((___getRevisionScore() / 10) * MaximumRevision);
        return _Value;
    }

    /**
     * @notice creator stake calculation
     */
    function getCreatorStake(
    uint32 DeadlineHours,
    uint8 MaximumRevision,
    uint256 rewardWei
    ) public view onlyRegistered returns (uint256) {
    return ___getCreatorStake(__getProjectValueNum(DeadlineHours, MaximumRevision, rewardWei, msg.sender));
    }

    /**
     * @notice member stake calculation
     */
    function getMemberRequiredStake(uint256 taskId) public view onlyRegistered returns (uint256) {
    Task storage t = Tasks[taskId];
    return (t.reward * memberStakePercentReward) / 100;
    }

    // =============================================================
    // INTERNAL HELPERS
    // =============================================================

    /**
     * @notice Read stored reputation for a given address
     * @dev Fallback to myPoint mapping if Users entry not present (backwards compatibility)
     */
    function __seeReputation(address who) internal view returns (uint32) {
        if (Users[who].isRegistered) {
            return Users[who].reputation;
        } else {
            return 0;
        }
    }

    /**
     * @notice Creator approves submission, triggering payout allocations (pull model)
     */
    function __approveTask(uint256 taskId)
        internal
    {
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
        if (Users[t.member].isRegistered) Users[t.member].reputation += ___getTaskAcceptMember();

        if (Users[t.creator].isRegistered) Users[t.creator].reputation += ___getTaskAcceptCreator();

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
     * @notice Counter for penalty complement (100 - NegPenalty)
     */
    function __CounterPenalty() internal view returns (uint32) {
        return uint32(100) - ___getNegPenalty();
    }

    /**
     * @notice Reset cancel request slot for a task
     */
    function __resetCancelRequest(uint256 taskId) internal {
        CancelRequest storage cr = CancelRequests[taskId];
        cr.requester = address(0);
        cr.counterparty = address(0);
        cr.expiry = 0;
        cr.status = TaskRejectRequest.None;
        cr.reason = "";
    }

//---------------------------------------------------- ADMIN & OWNER ------------------------------------------------------------

    /**
     * @notice Set algorithm scaling constant used in stake formulas.
     */
    function setMemberStakePercentageFromStake(uint256 NewmemberStakePercentReward) external onlyEmployes whenNotPaused {
        require(NewmemberStakePercentReward > 0, "can't be 0");
        require(NewmemberStakePercentReward <= 100, "can't be >100");
        memberStakePercentReward = NewmemberStakePercentReward;
        emit memberStakePercentRewardChanged(NewmemberStakePercentReward);
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

    function changeAccessControl(address _newAccesControl) external onlyOwner whenNotPaused {
        zero_Address(_newAccesControl);
        accessControl = IAccessControl(_newAccesControl);
        emit AccessControlChanged(_newAccesControl);
    }

    function changeStateVarAddress(address _newStateVar) external onlyOwner whenNotPaused {
        zero_Address(_newStateVar);
        stateVarUtils_init(_newStateVar);
        emit StateVarChanged(_newStateVar);
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
