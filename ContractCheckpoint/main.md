// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../Logic/AccesControl.sol";
import "../Logic/UserAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title TrustlessTeamProtocol v2
/// @notice Cleaned & safer refactor of TrustlessTeamProtocol focusing on core logic
/// @dev Pull-pay pattern, task lifecycle, submission, cancel logic, and revision handling implemented
contract TrustlessTeamProtocol is AccesControl, UserAccessControl, ReentrancyGuardUpgradeable, PausableUpgradeable, UUPSUpgradeable {

    // ===========================
    // ENUMS & STRUCTS
    // ===========================
    enum TaskStatus { NonExistent, OpenRegistration, Active, CancelRequested, Completed, Cancelled }
    enum UserTask { None, Request, Accepted, Submitted, Revision, Cancelled }
    enum TaskRejectRequest { None, Pending }
    enum SubmitStatus { NoneStatus, Pending, RevisionNeeded, Accepted }

    struct Task {
        uint256 taskId;
        TaskStatus status;
        address creator;
        address member;
        string title;
        string githubURL;
        uint256 reward;
        uint256 DeadlineInHours;
        uint256 DeadlineTimeInHours;
        uint256 createdAt;
        uint256 creatorStake;
        uint256 memberStake;
        uint8 maxRevision;
        bool isMemberStakeLocked;
        bool isCreatorStakeLocked;
        bool isRewardClaimed;
        bool exists;
    }

    struct JoinRequest {
        address applicant;
        uint256 stakeAmount;
        UserTask status;
        bool isPending;
        bool hasWithdrawn;
    }

    struct CancelRequest {
        address requester;
        address counterparty;
        uint256 expiry;
        TaskRejectRequest status;
        string reason;
    }

    struct TaskSubmit {
        string githubURL;
        address sender;
        string note;
        SubmitStatus status;
        uint8 revisionTime;
        uint256 newDeadline;
    }

    struct Counter {
        uint256 TotalTaskCreated;
        uint256 TotalTaskCompleted;
        uint256 TotalTaskFailed;
    }

    struct reputationPoint {
        uint32  CancelByMe;
        uint32  requestCancel;
        uint32  respondCancel;
        uint32  revision;
        uint32  taskAcceptCreator;
        uint32  taskAcceptMember;
        uint32  deadlineHitCreator;
        uint32  deadlineHitMember;
    }

    struct StateVar {
    uint64 cooldownInHour;
    uint32 minRevisionTimeInHour;
    uint32 NegPenalty;
    uint32 maxReward;
    uint32 feePercentage;
    uint32 maxStake;
    uint32 maxRevision;
    }

    // ===========================
    // STATE VARIABLES
    // ===========================
    mapping(uint256 => Task) public Tasks;
    mapping(uint256 => JoinRequest[]) public joinRequests;
    mapping(uint256 => CancelRequest) internal CancelRequests;
    mapping(uint256 => TaskSubmit) internal TaskSubmits;
    mapping(address => uint256) public withdrawable;
    mapping(address => uint32) public myPoint;
    mapping(address => Counter) internal Counters; 
    reputationPoint public reputationPoints;  //blum di initialize
    StateVar public StateVars;

    uint256 public taskCounter;
    uint256 internal feeCollected;
    uint256 public algoConstant;
    address payable public systemWallet;
    uint256[40] private ___gap;

    // ===========================
    // EVENTS
    // ===========================
    event TaskCreated(string Title, uint256 indexed taskId, address indexed creator, uint256 reward, uint256 creatorStake);
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
    event Withdrawal(address indexed user, uint256 amount);
    event cooldownInHourChanged(uint64 indexed newcooldownInHour);
    event maxStakeChanged(uint32 indexed newmaxStake);
    event kChanged(uint256 newK);
    event newsystemWallet(address indexed NewsystemWallet);
    event feeWithdarwedToSystemWallet(uint256 amount);

    // ===========================
    // ERRORS
    // ===========================
    error TaskDoesNotExist();
    error NotTaskCreator();
    error NotTaskMember();
    error AlreadyRequestedJoin();
    error TaskNotOpen();
    error CancelAlreadyRequested();
    error NoActiveCancelRequest();
    error NotCounterparty();
    error InsufficientStake();
    error StakeHitLimmit();
    error cancelOnlyBeforeMemberAccepted();
    error taskNotSubmitedYet();

    //creata task err
    error invalidTitle();
    error invalidGithubURL();
    error invalidDeadline();
    error tooMuchrevision();
    error invalidRewardAmount();

    // ===========================
    // MODIFIERS
    // ===========================
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

    // ===========================
    // INITIALIZER
    // ===========================
    function initialize(
        //(1)
        address _employeeAssignment,
        address _userRegistry,
        
        //(2)
        address payable _systemWallet,

        //(3)
        uint64 _cooldownInHour,
        uint32 _maxStake, 
        uint32 _NegPenalty,
        uint32 _maxReward,
        uint32 _minRevisionTimeInHour, 
        uint32 _feePercentage, 
        uint32 _maxRevision,

        //(4)
        uint32  _CancelByMe,
        uint32  _requestCancel,
        uint32  _respondCancel,
        uint32  _revision,
        uint32  _taskAcceptCreator,
        uint32  _taskAcceptMember,
        uint32  _deadlineHitCreator,
        uint32  _deadlineHitMember
        ) public initializer {

        // Validate addresses
        zero_Address(_systemWallet);
        zero_Address(_employeeAssignment);
        zero_Address(_userRegistry);

        // Initialize parent contracts first (1)
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        userRegistry = IUserRegister(_userRegistry);
        employeeAssignment = IEmployeeAssignment(_employeeAssignment);

        // Initialize contract state (2)
        systemWallet = _systemWallet;
        algoConstant = 1e3;
        taskCounter = 0;
        feeCollected = 0;

        //state var struct (3)
        StateVar storage sv = StateVars;
        require(_NegPenalty <= 100, "neg penalty can't be 100");
        sv.maxStake = _maxStake;
        sv.NegPenalty = _NegPenalty;
        sv.maxReward = _maxReward;
        sv.minRevisionTimeInHour = _minRevisionTimeInHour;
        sv.cooldownInHour = _cooldownInHour;
        sv.feePercentage = _feePercentage;
        sv.maxRevision = _maxRevision;

        //reputation point (4)
        reputationPoint storage rp = reputationPoints;
        rp.CancelByMe = _CancelByMe;
        rp.requestCancel = _requestCancel;
        rp.respondCancel = _respondCancel;
        rp.revision = _revision;
        rp.taskAcceptCreator = _taskAcceptCreator;
        rp.taskAcceptMember = _taskAcceptMember;
        rp.deadlineHitCreator = _deadlineHitCreator;
        rp.deadlineHitMember = _deadlineHitMember;
    }

    function _CounterPenalty() internal view returns (uint32) {
        StateVar storage sv = StateVars;
        uint32 neg = 100 - sv.NegPenalty;
        return neg;
    }

     function _resetCancelRequest(uint256 taskId) internal {
        CancelRequest storage cr = CancelRequests[taskId];
        cr.requester = address(0);
        cr.counterparty = address(0);
        cr.expiry = 0;
        cr.status = TaskRejectRequest.None;
        cr.reason = "";
    }

    function getMemberRequiredStake(uint256 taskId) public view returns (uint256) {
        Task storage t = Tasks[taskId];
        uint256 memberStake = (t.reward * (t.DeadlineTimeInHours + 1) * algoConstant) /
        ((_seeReputation(msg.sender) + 1) * (_seeReputation(t.creator) + 1) * (t.maxRevision + 1));
        return memberStake;
    }

    function getCreatorRequiredStakeFor(uint256 rewardWei, uint8 maxRevision, uint256 deadlineHours) public view returns (uint256) {
        uint256 creatorStake = (rewardWei * (uint256(maxRevision) + 1) * algoConstant) / ((_seeReputation(msg.sender) + 1) * (deadlineHours + 1));
        return creatorStake;
    }

    // ===========================
    // TASK LIFECYCLE FUNCTIONS
    // ===========================
    //gaada validasi input !
    function createTask(string memory Title, string memory GithubURL, uint256 _DeadlineHours, uint8 maximumRevision, uint256 RewardEther) external payable whenNotPaused onlyRegistered onlyUser callerZeroAddr{
        StateVar storage sv = StateVars;
        taskCounter++;
        uint256 taskId = taskCounter;
        uint256 _reward = RewardEther * 1 ether;

        if (bytes(Title).length == 0) revert invalidTitle();
        if (bytes(GithubURL).length == 0) revert invalidGithubURL();
        if (_DeadlineHours < sv.minRevisionTimeInHour) revert invalidDeadline();
        if (maximumRevision > sv.maxRevision) revert tooMuchrevision();
        if (RewardEther == 0) revert invalidRewardAmount();
        if (RewardEther > sv.maxReward) revert invalidRewardAmount();

        uint256 creatorStake = getCreatorRequiredStakeFor(RewardEther, maximumRevision, _DeadlineHours);
        if (sv.maxStake < creatorStake) revert StakeHitLimmit();
        uint256 fee = (creatorStake * sv.feePercentage) / 100;
        feeCollected += fee;
        uint256 total = _reward + creatorStake + fee;
        if (msg.value != total) revert InsufficientStake();

        Tasks[taskId] = Task({
            taskId: taskId,
            status: TaskStatus.Active,
            creator: msg.sender,
            member: address(0),
            title: Title,
            githubURL: GithubURL,
            reward: _reward,
            DeadlineInHours: 0,
            DeadlineTimeInHours: _DeadlineHours,
            createdAt: block.timestamp,
            creatorStake: creatorStake,
            memberStake: 0,
            maxRevision: maximumRevision,
            isMemberStakeLocked: false,
            isCreatorStakeLocked: true,
            isRewardClaimed: false,
            exists: true
        });
        Counters[msg.sender].TotalTaskCreated++;

        emit TaskCreated(Title, taskId, msg.sender, _reward, creatorStake);
    }

    function openRegistration(uint256 taskId) external taskExists(taskId) onlyTaskCreator(taskId) whenNotPaused {
        Task storage t = Tasks[taskId];
        require(t.status == TaskStatus.Active, "not active");
        t.status = TaskStatus.OpenRegistration;
        emit RegistrationOpened(taskId);
    }

    function closeRegistration(uint256 taskId) external taskExists(taskId) onlyTaskCreator(taskId) whenNotPaused {
        Task storage t = Tasks[taskId];
        require(t.status == TaskStatus.OpenRegistration, "not open");
        t.status = TaskStatus.Active;
        emit RegistrationClosed(taskId);
    }

    function requestJoinTask(uint256 taskId) external payable taskExists(taskId) whenNotPaused onlyRegistered onlyUser callerZeroAddr{
        StateVar storage sv = StateVars;
        Task storage t = Tasks[taskId];
        JoinRequest[] storage reqs = joinRequests[taskId];
        for (uint256 i = 0; i < reqs.length; i++) {
        if (reqs[i].applicant == msg.sender && reqs[i].isPending) {
        revert AlreadyRequestedJoin();
            }
        }

        if (t.status != TaskStatus.OpenRegistration) revert TaskNotOpen();
        if (msg.sender == t.creator) revert TaskNotOpen();
        uint256 memberStake = getMemberRequiredStake(taskId);
        if (sv.maxStake < msg.value) revert StakeHitLimmit();
        if (msg.value != memberStake) revert InsufficientStake();
        joinRequests[taskId].push(JoinRequest({
            applicant: msg.sender,
            stakeAmount: msg.value,
            status: UserTask.Request,
            isPending: true,
            hasWithdrawn: false
        }));
        emit JoinRequested(taskId, msg.sender, msg.value);
    }

    function approveJoinRequest(uint256 taskId, address _applicant) external taskExists(taskId) onlyTaskCreator(taskId) nonReentrant whenNotPaused {
        JoinRequest[] storage requests = joinRequests[taskId];
        Task storage t = Tasks[taskId];
        bool found = false;
        for (uint256 i = 0; i < requests.length; i++) {
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

        t.DeadlineInHours = block.timestamp + (t.DeadlineTimeInHours * 1 hours);
        t.status = TaskStatus.Active;

        emit JoinApproved(taskId, _applicant);
    }

    function rejectJoinRequest(uint256 taskId, address _applicant) external taskExists(taskId) onlyTaskCreator(taskId) whenNotPaused {
        JoinRequest[] storage requests = joinRequests[taskId];
        bool found = false;
        for (uint256 i = 0; i < requests.length; i++) {
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

    function requestCancel(uint256 taskId, string calldata reason) external whenNotPaused taskExists(taskId) {
        StateVar storage sv = StateVars;
        Task storage t = Tasks[taskId];
        CancelRequest storage cr = CancelRequests[taskId];
        reputationPoint storage rp = reputationPoints;
        if (cr.status == TaskRejectRequest.Pending) revert CancelAlreadyRequested();
        if (msg.sender != t.creator && msg.sender != t.member) revert NotTaskMember();
        if (t.member == address(0)) revert cancelOnlyBeforeMemberAccepted();
        address counterparty = (msg.sender == t.creator) ? t.member : t.creator;
        cr.requester = msg.sender;
        cr.counterparty = counterparty;
        cr.expiry = block.timestamp + (sv.cooldownInHour * 1 hours);
        cr.status = TaskRejectRequest.Pending;
        cr.reason = reason;
        t.status = TaskStatus.CancelRequested;
        if (myPoint[msg.sender] < rp.requestCancel) myPoint[msg.sender] = 0;
        else myPoint[msg.sender] -= rp.requestCancel;

        emit CancelRequestedEvent(taskId, msg.sender, reason, (sv.cooldownInHour * 1 hours));
    }

    function respondCancel(uint256 taskId, bool approve) external taskExists(taskId) whenNotPaused {
        Task storage t = Tasks[taskId];
        CancelRequest storage cr = CancelRequests[taskId];
        reputationPoint storage rp = reputationPoints;
        if (cr.status != TaskRejectRequest.Pending) revert NoActiveCancelRequest();
        if (msg.sender != cr.counterparty) revert NotCounterparty();
        if (t.member == address(0)) revert cancelOnlyBeforeMemberAccepted();

        if (block.timestamp > cr.expiry) {
            _resetCancelRequest(taskId);
            t.status = TaskStatus.Active;
            emit CancelResponded(taskId, false);
            return;
        }

        if (!approve) {
            _resetCancelRequest(taskId);
            t.status = TaskStatus.Active;
            emit CancelResponded(taskId, false);
            return;
        }

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
        if (myPoint[msg.sender] < rp.respondCancel) myPoint[msg.sender] = 0;
        else myPoint[msg.sender] -= rp.respondCancel;

        Counters[t.creator].TotalTaskFailed++;
        if (t.member != address(0)) Counters[t.member].TotalTaskFailed++;
        emit CancelResponded(taskId, true);
        return;
    }

    function cancelByMe(uint256 taskId) external taskExists(taskId) whenNotPaused {
        StateVar storage sv = StateVars;
        reputationPoint storage rp = reputationPoints;
        Task storage t = Tasks[taskId];
        if (msg.sender != t.creator && msg.sender != t.member) revert NotTaskMember();
        if (CancelRequests[taskId].status == TaskRejectRequest.Pending) revert CancelAlreadyRequested();
        if (t.status !=TaskStatus.Active) revert TaskNotOpen();

        if (msg.sender == t.member) {
            uint256 penaltyToCreator = (t.memberStake * sv.NegPenalty) / 100;
            uint256 memberReturn = (t.memberStake * _CounterPenalty()) / 100;
            withdrawable[t.creator] += t.creatorStake + t.reward + penaltyToCreator;
            withdrawable[t.member] += memberReturn;
            t.isMemberStakeLocked = false;
            t.isCreatorStakeLocked = false;
        } else {
            if (t.member == address(0)) revert cancelOnlyBeforeMemberAccepted();
            uint256 penaltyToMember = (t.creatorStake * sv.NegPenalty) / 100;
            uint256 creatorReturn = (t.creatorStake * _CounterPenalty()) / 100 + t.reward;
            withdrawable[t.member] += t.memberStake + penaltyToMember;
            withdrawable[t.creator] += creatorReturn;
            t.isMemberStakeLocked = false;
            t.isCreatorStakeLocked = false;
        }

        t.status = TaskStatus.Cancelled;
        if (myPoint[msg.sender] < rp.CancelByMe) myPoint[msg.sender] = 0;
        else myPoint[msg.sender] -= rp.CancelByMe;

        Counters[msg.sender].TotalTaskFailed++;

        emit TaskCancelledByMe(taskId, msg.sender);
    }

    function requestSubmitTask(uint256 taskId, string calldata PullRequestURL, string calldata Note) external onlyTaskMember(taskId) taskExists(taskId) whenNotPaused {
        Task storage t = Tasks[taskId];
        if (t.status != TaskStatus.Active) revert TaskNotOpen();
        if (t.member != msg.sender) revert NotTaskMember();
        TaskSubmits[taskId] = TaskSubmit({
            githubURL: PullRequestURL,
            sender: msg.sender,
            note: Note,
            status: SubmitStatus.Pending,
            revisionTime: 0,
            newDeadline: t.DeadlineInHours
        });
        emit TaskSubmitted(taskId, msg.sender, PullRequestURL);
    }

    function reSubmitTask(uint256 taskId, string calldata Note) external onlyTaskMember(taskId) taskExists(taskId) whenNotPaused {
        Task storage t = Tasks[taskId];
        TaskSubmit storage s = TaskSubmits[taskId];
        if (t.member != msg.sender) revert NotTaskMember();
        require(s.status == SubmitStatus.RevisionNeeded, "not in revision");
        require(s.revisionTime <= t.maxRevision, "revision limit exceeded");
        require(s.sender != address(0), "no submission");

        s.note = Note;
        s.status = SubmitStatus.Pending;

        if (s.revisionTime > t.maxRevision) {
            // too many revisions -> auto approve
            approveTask(taskId);
        }
        emit TaskReSubmitted(taskId, msg.sender);
    }

    function approveTask(uint256 taskId) public taskExists(taskId) onlyTaskCreator(taskId) nonReentrant whenNotPaused {
        reputationPoint storage rp = reputationPoints;
        Task storage t = Tasks[taskId];
        TaskSubmit storage s = TaskSubmits[taskId];

        if (t.status != TaskStatus.Active) revert TaskNotOpen();
        if (s.status != SubmitStatus.Pending) revert taskNotSubmitedYet();
        require(!t.isRewardClaimed, "already claimed");
        require(s.sender != address(0), "no submission");

        uint256 memberGet = t.reward + t.memberStake;
        uint256 creatorGet = t.creatorStake;

        withdrawable[t.member] += memberGet;
        withdrawable[t.creator] += creatorGet;

        t.isMemberStakeLocked = false;
        t.isCreatorStakeLocked = false;
        t.isRewardClaimed = true;

        t.isRewardClaimed = true;
        t.status = TaskStatus.Completed;

        myPoint[t.member] += rp.taskAcceptMember;
        myPoint[t.creator] += rp.taskAcceptCreator;

        Counters[t.creator].TotalTaskCompleted++;
        Counters[t.member].TotalTaskCompleted++;
        
        // clear submit
        s.githubURL = "";
        s.sender = address(0);
        s.note = "";
        s.status = SubmitStatus.Accepted;
        s.revisionTime = 0;
        s.newDeadline = 0;

        emit TaskApproved(taskId);
    }

    function requestRevision(uint256 taskId, string calldata Note, uint256 additionalDeadlineHours) external taskExists(taskId) onlyTaskCreator(taskId) whenNotPaused {
        StateVar storage sv = StateVars;
        Task storage t = Tasks[taskId];
        TaskSubmit storage s = TaskSubmits[taskId];
        reputationPoint storage rp = reputationPoints;
        if (t.member == address(0)) revert cancelOnlyBeforeMemberAccepted();
        require(s.status == SubmitStatus.Pending, "not pending");
        require(additionalDeadlineHours >= sv.minRevisionTimeInHour, "please give more time");
        uint256 aditionalDeadline = (additionalDeadlineHours * 1 hours);

        s.status = SubmitStatus.RevisionNeeded;
        s.note = Note;
        s.revisionTime++;
        t.DeadlineInHours = block.timestamp + aditionalDeadline;

        if (s.revisionTime > t.maxRevision) {
            // too many revisions -> auto approve
            approveTask(taskId);
        }
        if (myPoint[t.member] < rp.revision) myPoint[t.member] = 0;
        else myPoint[t.member] -= rp.revision;

        if (myPoint[t.creator] < rp.revision) myPoint[t.creator] = 0;
        else myPoint[t.creator] -= rp.revision;
        emit RevisionRequested(taskId, s.revisionTime, t.DeadlineInHours);
    }

    // ===========================
    // DEADLINE TRIGGER
    // ===========================
    function triggerDeadline(uint256 taskId) public taskExists(taskId) whenNotPaused {
        StateVar storage sv = StateVars;
        Task storage t = Tasks[taskId];
        reputationPoint storage rp = reputationPoints;
        if (t.status != TaskStatus.Active) revert TaskNotOpen();
        if (t.DeadlineInHours == 0) return;
        if (block.timestamp < t.DeadlineInHours) return;

        // handle late/expired: split memberStake (75/25) and creator keeps creatorStake?
        if (t.member != address(0) && t.memberStake > 0) {
            uint256 toMember = (t.memberStake * sv.NegPenalty) / 100;
            uint256 toCreator = (t.memberStake * _CounterPenalty()) / 100;

            withdrawable[t.member] += toMember;
            withdrawable[t.creator] += toCreator + t.creatorStake + t.reward; // decide to return creator funds
        } else {
            // no member: return creator stake + reward
            withdrawable[t.creator] += t.creatorStake + t.reward;
        }

        if (myPoint[t.member] < rp.deadlineHitMember) myPoint[t.member] = 0;
        else myPoint[t.member] -= rp.deadlineHitMember;

        if (myPoint[t.creator] < rp.deadlineHitCreator) myPoint[t.creator] = 0;
        else myPoint[t.creator] -= rp.deadlineHitCreator;

        t.status = TaskStatus.Cancelled;
        Counters[t.creator].TotalTaskFailed++;
        Counters[t.member].TotalTaskFailed++;

        emit DeadlineTriggered(taskId);
    }

    // ===========================
    // PULL PAYMENTS
    // ===========================
    function withdraw() external nonReentrant onlyRegistered whenNotPaused {
        uint256 amount = withdrawable[msg.sender];
        require(amount > 0, "no funds");
        withdrawable[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "withdraw failed");

        emit Withdrawal(msg.sender, amount);
    }

    // ===========================
    // READ HELPERS
    // ===========================
    function getJoinRequests(uint256 taskId) external view onlyRegistered returns (JoinRequest[] memory) {
        return joinRequests[taskId];
    }

    function getTaskSubmit(uint256 taskId) external view onlyRegistered returns (TaskSubmit memory) {
        return TaskSubmits[taskId];
    }

    function getWithdrawableAmount() external view onlyRegistered returns(uint256) {
        return withdrawable[msg.sender];
    }

    // Fallback/receive to prevent accidental ETH
    receive() external payable {
        revert();
    }

    fallback() external payable {
        revert();
    }

//=============================================================================================================================================

    // regular state var
    function setAlgoConstant(uint256 newAlgoConstant) external onlyEmployes whenNotPaused {
        require(newAlgoConstant > 0, "can't be 0");
        algoConstant = newAlgoConstant;
        emit kChanged(newAlgoConstant);
    }

    function withdrawToSystemWallet() external onlyEmployes nonReentrant whenNotPaused {
        uint256 amount = feeCollected;
        feeCollected = 0;
        (bool ok, ) = systemWallet.call{value: amount}("");
        require(ok, "withdraw failed");
        emit feeWithdarwedToSystemWallet(amount);
    }

    function changeSystemwallet(address payable _NewsystemWallet) external onlyEmployes whenNotPaused {
        zero_Address(_NewsystemWallet);
        systemWallet = _NewsystemWallet;
        emit newsystemWallet(_NewsystemWallet);
    }



    // state Var struct
   function setCooldownHour(uint64 newCooldown) external onlyEmployes whenNotPaused {
        StateVar storage sv = StateVars;
        require(newCooldown > 0, "can't be 0");
        sv.cooldownInHour = newCooldown;
        emit cooldownInHourChanged(newCooldown);
    }

    function setMaxStake(uint32 newMaxStake) external onlyEmployes whenNotPaused {
        StateVar storage sv = StateVars;
        require(newMaxStake > 0, "can't be 0");
        sv.maxStake = newMaxStake;
        emit maxStakeChanged(newMaxStake);
    }
    function setNegativePenalty(uint32 newNegPenalty) external onlyEmployes whenNotPaused {
        StateVar storage sv = StateVars;
        require(newNegPenalty <= 100, "neg penalty can't be 100");
        sv.NegPenalty = newNegPenalty;
    }

    function setMinRevisionTimeInHour(uint32 _minRevisionTimeInHour) external onlyEmployes whenNotPaused {
        StateVar storage sv = StateVars;
        sv.minRevisionTimeInHour = _minRevisionTimeInHour;
    }

    function setfeePercentage(uint32 newfeePercentage) external onlyEmployes whenNotPaused {
        StateVar storage sv = StateVars;
        sv.feePercentage = newfeePercentage;
    }

    function setMaxReward (uint32 _maxReward) external onlyEmployes whenNotPaused {
        StateVar storage sv = StateVars;
        sv.maxReward = _maxReward;
    }


    // penalty point
    function setPenaltyPoint(
        uint32  newCancelByMe,
        uint32  newrequestCancel,
        uint32  newrespondCancel,
        uint32  newrevision,
        uint32  newtaskAcceptCreator,
        uint32  newtaskAcceptMember,
        uint32  newdeadlineHitCreator,
        uint32  newdeadlineHitMember
        ) external onlyEmployes whenNotPaused {
            reputationPoint storage rp = reputationPoints;
            rp.CancelByMe = newCancelByMe;
            rp.requestCancel = newrequestCancel;
            rp.respondCancel = newrespondCancel;
            rp.revision = newrevision;
            rp.taskAcceptCreator = newtaskAcceptCreator;
            rp.taskAcceptMember = newtaskAcceptMember;
            rp.deadlineHitCreator = newdeadlineHitCreator;
            rp.deadlineHitMember = newdeadlineHitMember;
        }


    // export data    
     function seeMyReputation(address _user) external view returns (uint32) {
        return myPoint[_user];
    }

    function seeMyCompleteCounter(address _user) external view returns (uint256) {
        return Counters[_user].TotalTaskCompleted;
    }

    function seeMyFailedCounter(address _user) external view returns (uint256) {
        return Counters[_user].TotalTaskFailed;
    }

    function seeMyCreatedCounter(address _user) external view returns (uint256) {
        return Counters[_user].TotalTaskCreated;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner whenNotPaused {}
}