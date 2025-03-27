// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract JPStaking is ERC20, ERC20Burnable, Ownable, ReentrancyGuard, Pausable {

    // --- Token Configuration ---
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18; // 1B tokens
    uint256 public constant ICO_ALLOCATION = 400_000_000 * 10**18; // 40% for ICO
    uint256 public constant STAKING_REWARDS = 300_000_000 * 10**18; // 30% for staking
    
    // --- Core Variables ---
    uint256 public icoEndTime;
    uint256 public totalStaked;
    uint256 public totalParticipants;
    address public nftContract;
    mapping(address => uint256) public userStakedAmount;
    mapping(address => uint256) public userLastUpdate;
    mapping(address => uint256) public userPendingRewards;

    // --- ICO Configuration ---
    uint256 public constant MIN_CONTRIBUTION = 0.1 ether;
    uint256 public constant MAX_CONTRIBUTION = 100 ether;
    uint256 public icoPrice = 0.0001 ether; // 1 token = 0.0001 ETH
    uint256 public totalRaised;
    bool public icoActive;

    // --- Staking Tiers ---
    enum StakingTier { Bronze, Silver, Gold, Platinum, Diamond }
    struct TierInfo {
        uint256 minStake;        // Minimum tokens to qualify
        uint256 rewardMultiplier; // Base reward multiplier (in basis points)
        uint256 lockPeriod;      // Minimum lock period in seconds
        uint256 maxStake;        // Maximum stake for this tier
        uint256 nftBoost;        // Additional boost % if holding specific NFT
    }
    
    mapping(StakingTier => TierInfo) public tiers;
    mapping(address => StakingTier) public userTier;

    // --- Advanced Staking Structures ---
    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lockPeriod;
        StakingTier tier;
        bool active;
        uint256 nftBoostId;     // Optional NFT boost
    }
    
    struct GovernanceProposal {
        uint256 id;
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256 yesVotes;
        uint256 noVotes;
        bool executed;
        address proposer;
    }

    // --- Storage ---
    mapping(address => Stake[]) public userStakes;
    mapping(address => uint256) public userGovernancePower;
    mapping(uint256 => GovernanceProposal) public proposals;
    uint256 public proposalCount;
    mapping(address => mapping(uint256 => bool)) public hasVoted; // userAddress => proposalId => True/False

    // --- Dynamic Reward System ---
    uint256 public baseRewardRate = 50; // 0.5% daily base rate (in basis points)
    uint256 public rewardPool = STAKING_REWARDS;
    uint256 public rewardAdjustmentFactor; // Dynamic adjustment based on participation

    // --- Events ---
    event ICOContribution(address indexed contributor, uint256 amount, uint256 tokens);
    event Staked(address indexed user, uint256 amount, StakingTier tier, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount, uint256 reward);
    event RewardClaimed(address indexed user, uint256 amount);
    event ProposalCreated(uint256 indexed proposalId, address proposer, string description);
    event Voted(address indexed voter, uint256 proposalId, bool support);
    event ProposalExecuted(uint256 indexed proposalId);

    constructor(address _nftContract) 
        ERC20("JP Staking Token", "JPST")
        Ownable(msg.sender)
    {
        nftContract = _nftContract;
        _mint(address(this), TOTAL_SUPPLY);
        
        // Initialize staking tiers 
        // [Min tokens to qualify][Base reward multiplier][Min lock period][Maximum stake][Additional boost % if holding specific NFT]
        tiers[StakingTier.Bronze] = TierInfo(1000 * 10**18, 100, 30 days, 10000 * 10**18, 5);
        tiers[StakingTier.Silver] = TierInfo(10000 * 10**18, 125, 60 days, 50000 * 10**18, 10);
        tiers[StakingTier.Gold] = TierInfo(50000 * 10**18, 150, 90 days, 200000 * 10**18, 15);
        tiers[StakingTier.Platinum] = TierInfo(200000 * 10**18, 200, 180 days, 500000 * 10**18, 20);
        tiers[StakingTier.Diamond] = TierInfo(500000 * 10**18, 300, 365 days, TOTAL_SUPPLY, 30);

        icoActive = true;
        icoEndTime = block.timestamp + 30 days;
    }

    // --- ICO Functions ---

    function contribute() 
        external 
        payable 
        whenNotPaused 
        nonReentrant 
    {
        require(icoActive && block.timestamp <= icoEndTime, "ICO not active");
        require(msg.value >= MIN_CONTRIBUTION && msg.value <= MAX_CONTRIBUTION, "Invalid contribution");
        
        uint256 tokens = (msg.value * 10**18) / icoPrice;
        require(totalRaised + tokens <= ICO_ALLOCATION, "ICO allocation exceeded");

        totalRaised += tokens;
        totalParticipants++;
        _transfer(address(this), msg.sender, tokens);

        emit ICOContribution(msg.sender, msg.value, tokens);
    }

    function endICO() external onlyOwner {
        require(icoActive, "ICO already ended");
        icoActive = false;
        icoEndTime = block.timestamp;
        
        // Burn unsold ICO tokens
        uint256 unsold = ICO_ALLOCATION - totalRaised;
        if (unsold > 0) {
            _burn(address(this), unsold);
        }
    }

    // --- Staking Functions ---

    function stake(
        uint256 _amount, 
        uint256 _lockPeriod, 
        uint256 _nftId
    ) 
        external 
        whenNotPaused 
        nonReentrant 
    {
        require(_amount > 0, "Invalid amount");
        require(balanceOf(msg.sender) >= _amount, "Insufficient balance");
        
        StakingTier tier = _determineTier(_amount);
        require(_lockPeriod >= tiers[tier].lockPeriod, "Lock period too short");
        require(_amount <= tiers[tier].maxStake, "Exceeds tier max stake");

        // NFT boost validation
        uint256 nftBoost = 0;
        if (_nftId > 0 && IERC721(nftContract).ownerOf(_nftId) == msg.sender) {
            nftBoost = tiers[tier].nftBoost;
        }

        _transfer(msg.sender, address(this), _amount);
        totalStaked += _amount;
        
        userStakes[msg.sender].push(Stake({
            amount: _amount,
            startTime: block.timestamp,
            lockPeriod: _lockPeriod,
            tier: tier,
            active: true,
            nftBoostId: _nftId
        }));

        userStakedAmount[msg.sender] += _amount;
        userLastUpdate[msg.sender] = block.timestamp;
        userTier[msg.sender] = tier;
        userGovernancePower[msg.sender] += _amount;
        
        _updateRewardAdjustment();
        emit Staked(msg.sender, _amount, tier, _lockPeriod);
    }

    function unstake(
        uint256 _stakeIndex
    ) 
        external 
        nonReentrant 
    {
        Stake storage _stake = userStakes[msg.sender][_stakeIndex];
        require(_stake.active, "Stake not active");
        require(block.timestamp >= _stake.startTime + _stake.lockPeriod, "Lock period not ended");

        uint256 reward = calculateReward(msg.sender, _stakeIndex);
        
        require(rewardPool >= reward, "Insufficient reward pool");
        
        _stake.active = false;
        totalStaked -= _stake.amount;
        rewardPool -= reward;
        userStakedAmount[msg.sender] -= _stake.amount;
        userGovernancePower[msg.sender] -= _stake.amount;

        _transfer(address(this), msg.sender, _stake.amount);
        if (reward > 0) {
            _mint(msg.sender, reward);
        }

        _updateRewardAdjustment();
        emit Unstaked(msg.sender, _stake.amount, reward);
    }

    function claimRewards() external nonReentrant {
        uint256 totalReward = 0;
        for (uint256 i = 0; i < userStakes[msg.sender].length; i++) {
            if (userStakes[msg.sender][i].active) {
                totalReward += calculateReward(msg.sender, i);
            }
        }
        
        require(totalReward > 0, "No rewards to claim");
        require(rewardPool >= totalReward, "Insufficient reward pool");

        rewardPool -= totalReward;
        userLastUpdate[msg.sender] = block.timestamp;
        _mint(msg.sender, totalReward);

        emit RewardClaimed(msg.sender, totalReward);
    }

    // --- Governance Functions ---

    function createProposal(
        string memory _description
    ) external {
        require(userStakedAmount[msg.sender] >= 10000 * 10**18, "Insufficient stake for proposal");
        
        proposalCount++;
        proposals[proposalCount] = GovernanceProposal({
            id: proposalCount,
            description: _description,
            startTime: block.timestamp,
            endTime: block.timestamp + 7 days,
            yesVotes: 0,
            noVotes: 0,
            executed: false,
            proposer: msg.sender
        });

        emit ProposalCreated(proposalCount, msg.sender, _description);
    }

    function vote(uint256 _proposalId, bool _support) external {
        GovernanceProposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.startTime && block.timestamp <= proposal.endTime, "Voting not active");
        require(!hasVoted[msg.sender][_proposalId], "Already voted");
        require(userGovernancePower[msg.sender] > 0, "No voting power");

        hasVoted[msg.sender][_proposalId] = true;
        if (_support) {
            proposal.yesVotes += userGovernancePower[msg.sender];
        } else {
            proposal.noVotes += userGovernancePower[msg.sender];
        }

        emit Voted(msg.sender, _proposalId, _support);
    }

    function executeProposal(uint256 _proposalId) external onlyOwner {
        GovernanceProposal storage proposal = proposals[_proposalId];
        require(block.timestamp > proposal.endTime, "Voting not ended");
        require(!proposal.executed, "Already executed");
        require(proposal.yesVotes > proposal.noVotes, "Proposal not approved");

        proposal.executed = true;
        // Implementation of proposal execution would depend on specific governance actions
        emit ProposalExecuted(_proposalId);
    }

    // --- Internal Functions ---

    function _determineTier(uint256 _amount) internal view returns (StakingTier) {
        if (_amount >= tiers[StakingTier.Diamond].minStake) return StakingTier.Diamond;
        if (_amount >= tiers[StakingTier.Platinum].minStake) return StakingTier.Platinum;
        if (_amount >= tiers[StakingTier.Gold].minStake) return StakingTier.Gold;
        if (_amount >= tiers[StakingTier.Silver].minStake) return StakingTier.Silver;
        return StakingTier.Bronze;
    }

    function calculateReward(address _user, uint256 _stakeIndex) public view returns (uint256) {
        Stake memory _stake = userStakes[_user][_stakeIndex];
        if (!_stake.active) return 0;

        uint256 timeElapsed = block.timestamp - userLastUpdate[_user];
        // uint256 baseReward = _stake.amount.mul(baseRewardRate).mul(timeElapsed).div(1 days).div(10000); // Basis points
        uint256 baseReward = (_stake.amount * baseRewardRate * timeElapsed) / (1 days * 10000);         
        
        uint256 tierMultiplier = tiers[_stake.tier].rewardMultiplier;
        uint256 nftBoost = _stake.nftBoostId > 0 ? tiers[_stake.tier].nftBoost : 0;
        
        return (baseReward * (tierMultiplier + nftBoost) * rewardAdjustmentFactor) / 10000;

    }

    function _updateRewardAdjustment() internal {
        if (totalStaked > 0) {
            rewardAdjustmentFactor = (TOTAL_SUPPLY * 10000) / totalStaked;
            if (rewardAdjustmentFactor > 20000) rewardAdjustmentFactor = 20000; // Cap at 2x
            if (rewardAdjustmentFactor < 5000) rewardAdjustmentFactor = 5000;   // Floor at 0.5x
        }
    }

    // --- Admin Functions ---

    function updateBaseRewardRate(uint256 _newRate) external onlyOwner {
        require(_newRate <= 1000, "Rate too high"); // Max 10%
        baseRewardRate = _newRate;
    }

    function withdrawFunds() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        payable(owner()).transfer(balance);
    }

    // --- View Functions ---

    function getUserStakes(address _user) external view returns (Stake[] memory) {
        return userStakes[_user];
    }

    function getTotalRewards(address _user) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < userStakes[_user].length; i++) {
            if (userStakes[_user][i].active) {
                total = total + calculateReward(_user, i);
            }
        }
        return total;
    }
}