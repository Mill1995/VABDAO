// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "../libraries/Ownable.sol";
import "../libraries/Helper.sol";
import "../interfaces/IVabbleDAO.sol";
import "../interfaces/IStakingPool.sol";
import "../interfaces/IFilmBoard.sol";
import "hardhat/console.sol";

contract Vote is Ownable, ReentrancyGuard {
    
    event FilmsVoted(uint256[] indexed filmIds, uint256[] status, address voter);
    event FilmVotePeriodUpdated(uint256 filmVotePeriod);
    event FilmIdsApproved(uint256[] filmIds, uint256[] approvedIds, address caller);
    event AuditorReplaced(address auditor);

    struct Proposal {
        uint256 stakeAmount_1;  // staking amount of voter with status(yes)
        uint256 stakeAmount_2;  // staking amount of voter with status(no)
        uint256 stakeAmount_3;  // staking amount of voter with status(abstain)
        uint256 voteCount;      // number of accumulated votes
        uint256 voteStartTime;  // vote start time for a film
    }

    struct AgentProposal {
        uint256 yes;           // yes
        uint256 no;            // no
        uint256 abtain;        // abstain
        uint256 voteCount;     // number of accumulated votes
        uint256 voteStartTime; // vote start time for an agent
    }

    IERC20 public PAYOUT_TOKEN; // VAB token  
    address public VABBLE_DAO;
    address public STAKING_POOL;
    address public FILM_BOARD;

    bool public isInitialized;         // check if vote contract initialized or not
    uint256 public filmVotePeriod;     // film vote period
    uint256 public boardVotePeriod;    // filmBoard vote period
    uint256 public boardVoteWeight;    // filmBoard member's vote weight
    uint256 public agentVotePeriod;    // vote period for replacing auditor
    uint256 public disputeGracePeriod; // grace period for replacing Auditor
    uint256[] private approvedFilmIds; // approved film ID list

    mapping(uint256 => Proposal) public proposal;                       // (filmId => Proposal)
    mapping(address => Proposal) public filmBoardProposal;              // (filmBoard candidate => Proposal)  
    mapping(address => mapping(uint256 => bool)) public voteAttend;     // (staker => (filmId => true/false))
    mapping(address => mapping(address => bool)) public boardVoteAttend;// (staker => (filmBoard candidate => true/false))
    
    mapping(address => AgentProposal) public agentProposal;           // (agent => AgentProposal)
    mapping(address => mapping(address => bool)) public votedToAgent; // (staker => (agent => true/false)) 
    // mapping(address => bool) public agentList;    
    
    modifier initialized() {
        require(isInitialized, "Need initialized!");
        _;
    }

    /// @notice Allow to vote for only staker(stakingAmount > 0)
    modifier onlyStaker() {
        require(msg.sender != address(0), "Staker Zero address");
        require(IStakingPool(STAKING_POOL).getStakeAmount(msg.sender) > 0, "Not staker");
        _;
    }

    modifier onlyAvailableStaker() {
        require(IStakingPool(STAKING_POOL).getStakeAmount(msg.sender) >= PAYOUT_TOKEN.totalSupply(), "Not available staker");
        _;
    }

    constructor() {}

    /// @notice Set VabbleDAO contract address and stakingPool address by only auditor
    function initializeVote(
        address _vabbleDAO,
        address _stakingPool,
        address _filmBoard,
        address _payoutToken
    ) external onlyAuditor {
        require(!isInitialized, "initializeVote: Already initialized vote");
        require(_vabbleDAO != address(0) && Helper.isContract(_vabbleDAO), "initializeVote: Zero vabbleDAO address");
        VABBLE_DAO = _vabbleDAO;        
        require(_stakingPool != address(0) && Helper.isContract(_stakingPool), "initializeVote: Zero stakingPool address");
        STAKING_POOL = _stakingPool;
        require(_filmBoard != address(0) && Helper.isContract(_filmBoard), "initializeVote: Zero filmBoard address");
        FILM_BOARD = _filmBoard;
        require(_payoutToken != address(0), "initializeVote: Zero VAB Token address");
        PAYOUT_TOKEN = IERC20(_payoutToken);        

        filmVotePeriod = 10 days;   
        boardVotePeriod = 10 days;
        agentVotePeriod = 10 days;
        boardVoteWeight = 3000;       // 30% = 3000
        disputeGracePeriod = 30 days;     
        isInitialized = true;
    }        

    /// @notice Vote to multi films from a VAB holder
    function voteToFilms(bytes calldata _voteData) external onlyStaker initialized nonReentrant {
        require(_voteData.length > 0, "voteToFilm: Bad items length");
        (
            uint256[] memory filmIds_, 
            uint256[] memory voteInfos_
        ) = abi.decode(_voteData, (uint256[], uint256[]));
        
        require(filmIds_.length == voteInfos_.length, "voteToFilm: Bad votes length");

        uint256[] memory votedFilmIds = new uint256[](filmIds_.length);
        uint256[] memory votedStatus = new uint256[](filmIds_.length);

        for (uint256 i; i < filmIds_.length; i++) { 
            if(__voteToFilm(filmIds_[i], voteInfos_[i])) {
                votedFilmIds[i] = filmIds_[i];
                votedStatus[i] = voteInfos_[i];
            }
        }

        emit FilmsVoted(votedFilmIds, votedStatus, msg.sender);
    }

    function __voteToFilm(uint256 _filmId, uint256 _voteInfo) private returns(bool) {
        require(!voteAttend[msg.sender][_filmId], "_voteToFilm: Already voted");        

        Proposal storage _proposal = proposal[_filmId];
        if(_proposal.voteCount == 0) {
            _proposal.voteStartTime = block.timestamp;
        }
        _proposal.voteCount++;

        uint256 stakingAmount = IStakingPool(STAKING_POOL).getStakeAmount(msg.sender);

        // If filme is for funding and voter is film board member, more weight(30%) per vote
        if(IVabbleDAO(VABBLE_DAO).isForFund(_filmId) && IFilmBoard(FILM_BOARD).isWhitelist(msg.sender)) {
            stakingAmount *= (boardVoteWeight + 10000) / 10000; // (3000+10000)/10000=1.3
        }        

        if(_voteInfo == 1) {
            _proposal.stakeAmount_1 += stakingAmount;   // Yes
        } else if(_voteInfo == 2) {
            _proposal.stakeAmount_2 += stakingAmount;   // No
        } else {
            _proposal.stakeAmount_3 += stakingAmount;   // Abstain
        }

        voteAttend[msg.sender][_filmId] = true;
        IFilmBoard(FILM_BOARD).updateLastVoteTime(msg.sender);

        // Example: withdrawTime is 6/15 and voteStartTime is 6/10, votePeriod is 10 days
        // In this case, we update the withdrawTime to sum(6/20) of voteStartTime and votePeriod
        // so, staker cannot unstake his amount till 6/20
        uint256 withdrawableTime =  IStakingPool(STAKING_POOL).getWithdrawableTime(msg.sender);
        if (_proposal.voteStartTime + filmVotePeriod > withdrawableTime) {
            IStakingPool(STAKING_POOL).updateWithdrawableTime(msg.sender, _proposal.voteStartTime + filmVotePeriod);
        }

        return true;
    }

    /// @notice Approve multi films that votePeriod has elapsed after votePeriod(10 days) by auditor
    // if noFund is true, Approved for listing and if noFund is false, Approved for funding
    function approveFilms(uint256[] memory _filmIds) external onlyAuditor {
        for (uint256 i; i < _filmIds.length; i++) {
            // Example: stakeAmount of "YES" is 2000 and stakeAmount("NO") is 1000, stakeAmount("ABSTAIN") is 500 in 10 days(votePeriod)
            // In this case, Approved since 2000 > 1000 + 500
            if(block.timestamp - proposal[_filmIds[i]].voteStartTime > filmVotePeriod) {
                if(proposal[_filmIds[i]].stakeAmount_1 > proposal[_filmIds[i]].stakeAmount_2 + proposal[_filmIds[i]].stakeAmount_3) {                    
                    bool isFund = IVabbleDAO(VABBLE_DAO).isForFund(_filmIds[i]);
                    IVabbleDAO(VABBLE_DAO).approveFilm(_filmIds[i], isFund);
                    approvedFilmIds.push(_filmIds[i]);
                }
            }        
        }        

        emit FilmIdsApproved(_filmIds, approvedFilmIds, msg.sender);
    }

    /// @notice A staker vote to agents for replacing Auditor
    // _vote: 1,2,3 => Yes, No, Abstain
    function voteToAgent(address _agent, uint256 _voteInfo) external onlyAvailableStaker nonReentrant {
        require(!votedToAgent[msg.sender][_agent], "voteToAgent: Already voted");
        require(msg.sender != address(0), "voteToAgent: Zero caller address");
        require(IFilmBoard(FILM_BOARD).isAgent(_agent), "voteToAgent: Not agent address");

        AgentProposal storage _agentProposal = agentProposal[_agent];
        if(_agentProposal.voteCount == 0) {
            _agentProposal.voteStartTime = block.timestamp;
        }

        if(_voteInfo == 1) {
            _agentProposal.yes += 1;
        } else if(_voteInfo == 2) {
            _agentProposal.no += 1;
        } else {
            _agentProposal.abtain += 1;
        }

        _agentProposal.voteCount++;
        votedToAgent[msg.sender][_agent] = true;
    }

    /// @notice Replace Auditor based on vote result
    function replaceAuditor() external onlyAvailableStaker nonReentrant {
        uint256 startTime;
        AgentProposal storage _agentProposal;

        address[] memory agents = IFilmBoard(FILM_BOARD).getAgentArray();
        for(uint256 i; i < agents.length; i++) {
            _agentProposal = agentProposal[agents[i]];
            startTime = _agentProposal.voteStartTime;
            require(agentVotePeriod < block.timestamp - startTime);

            if(IFilmBoard(FILM_BOARD).isAgent(agents[i]) && disputeGracePeriod < block.timestamp - startTime) {
                if(_agentProposal.voteCount > 0 && _agentProposal.yes > _agentProposal.no + _agentProposal.abtain) {
                    auditor = agents[i];
                }                
            }
        }

        emit AuditorReplaced(auditor);
    }
    // ================ Auditor governance by the Staker END =================
    function voteToFilmBoard(address _candidate, uint256 _voteInfo) external onlyStaker nonReentrant {
        require(!boardVoteAttend[msg.sender][_candidate], "voteToFilmBoard: Already voted");        
        require(!IFilmBoard(FILM_BOARD).isWhitelist(_candidate), "voteToFilmBoard: Already film board member");

        Proposal storage fbp = filmBoardProposal[_candidate];
        if(fbp.voteCount == 0) {
            fbp.voteStartTime = block.timestamp;
        }
        fbp.voteCount++;

        uint256 stakingAmount = IStakingPool(STAKING_POOL).getStakeAmount(msg.sender);

        if(_voteInfo == 1) {
            fbp.stakeAmount_1 += stakingAmount;   // Yes
        } else if(_voteInfo == 2) {
            fbp.stakeAmount_2 += stakingAmount;   // No
        } else {
            fbp.stakeAmount_3 += stakingAmount;   // Abstain
        }

        boardVoteAttend[msg.sender][_candidate] = true;
    }
    
    function addFilmBoard(address _member) external onlyStaker nonReentrant {
        Proposal storage fbp = filmBoardProposal[_member];
        require(block.timestamp - fbp.voteStartTime > boardVotePeriod, "addFilmBoard: vote period yet");

        if(fbp.stakeAmount_1 > fbp.stakeAmount_2 + fbp.stakeAmount_3) { 
            IFilmBoard(FILM_BOARD).addFilmBoardMember(_member);
        }         
    }

    /// @notice Update vote period by only auditor
    function updateFilmVotePeriod(uint256 _filmVotePeriod) external onlyAuditor nonReentrant {
        filmVotePeriod = _filmVotePeriod;

        emit FilmVotePeriodUpdated(_filmVotePeriod);
    }

    /// @notice Get proposal film Ids
    function getApprovedFilmIds() external view returns(uint256[] memory) {
        return approvedFilmIds;
    }
}