// ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
// 88             88            B8         B8         B8
//  88           88             88         88         88
//   88         88              88         88         88 
//    88       88   .d88888b.   88b8888b.  88b8888b.  88  .d88888b. 
//     88     88    88'   `88   88'   `88  88'   `88  88  88'   `8b
//      88   88     88     88   88     88  88     88  88  88b8888P`
//       88 88      88.   .88   88.   .88  88.   .88  88  88.   
//        88        `88888P`88  BBP88888'  BBP88888`  88  `888888P
// ooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "../libraries/Helper.sol";
import "../interfaces/IUniHelper.sol";
import "../interfaces/IStakingPool.sol";
import "../interfaces/IProperty.sol";
import "../interfaces/IOwnablee.sol";
import "../interfaces/IFactoryFilmNFT.sol";
import "../interfaces/IVabbleDAO.sol";
import "hardhat/console.sol";

contract VabbleDAO is ReentrancyGuard {
    using Counters for Counters.Counter;

    event FilmProposalCreated(uint256 filmId, uint256 noVote, uint256 fundType, address studio, uint256 createTime);
    event FilmProposalUpdated(uint256 filmId, uint256 fundType, address studio, uint256 updateTime);  
    event FinalFilmSetted(address[] users, uint256[] filmIds, uint256[] watchedPercents, uint256[] rentPrices, uint256 setTime);
    event FilmFundPeriodUpdated(uint256 filmId, address studio, uint256 fundPeriod, uint256 updateTime);
    
    address public immutable OWNABLE;         // Ownablee contract address
    address public immutable VOTE;            // Vote contract address
    address public immutable STAKING_POOL;    // StakingPool contract address
    address public immutable UNI_HELPER;      // UniHelper contract address
    address public immutable DAO_PROPERTY;
    address public immutable FILM_NFT_FACTORY;  
    
    uint256[] private proposalFilmIds;    
    uint256[] private approvedFundingFilmIds;
    uint256[] private approvedListingFilmIds;
    
    mapping(uint256 => IVabbleDAO.Film) public filmInfo;             // Each film information(filmId => Film)
    mapping(address => uint256[]) private userFinalFilmIds;
    mapping(address => uint256[]) private userFilmProposalIds;        // (studio => filmId list)
    mapping(address => uint256[]) private userApprovedFilmIds;        // (studio => filmId list)
    mapping(uint256 => uint256) private finalVABPayout;           // (filmId => VAB amount)

    uint256 public lastRunTime;

    Counters.Counter public filmCount;          // filmId is from No.1

    modifier onlyVote() {
        require(msg.sender == VOTE, "caller is not the vote contract");
        _;
    }
    modifier onlyAuditor() {
        require(msg.sender == IOwnablee(OWNABLE).auditor(), "caller is not the auditor");
        _;
    }  

    receive() external payable {}
    
    constructor(
        address _ownable,
        address _uniHelper,
        address _vote,
        address _staking,
        address _property,
        address _filmNftFactory
    ) {        
        require(_ownable != address(0), "ownableContract: Zero address");
        OWNABLE = _ownable;     
        require(_uniHelper != address(0), "uniHelperContract: Zero address");
        UNI_HELPER = _uniHelper;
        require(_vote != address(0), "voteContract: Zero address");
        VOTE = _vote;
        require(_staking != address(0), "stakingContract: Zero address");
        STAKING_POOL = _staking;      
        require(_property != address(0), "daoProperty: Zero address");
        DAO_PROPERTY = _property; 
        require(_filmNftFactory!= address(0), "setup: zero factoryContract address");
        FILM_NFT_FACTORY = _filmNftFactory;  
    }

    // ======================== Film proposal ==============================
    /// @notice Staker create multi proposal for a lot of films | noVote: if 0 => false, 1 => true
    /// _feeToken : Matic/USDC/USDT, not VAB
    function proposalFilmCreate(uint256 _fundType, uint256 _noVote, address _feeToken) external payable nonReentrant {     
        require(_feeToken != IOwnablee(OWNABLE).PAYOUT_TOKEN(), "proposalFilm: not allowed VAB");
        if(_feeToken != address(0)) {
            require(IOwnablee(OWNABLE).isDepositAsset(_feeToken), "proposalFilm: not allowed asset");   
        }
        if(_fundType == 0) require(_noVote == 0, "proposalFilm: should pass vote");
        
        __paidFee(_feeToken, _noVote);
 
        filmCount.increment();
        uint256 filmId = filmCount.current();

        IVabbleDAO.Film storage fInfo = filmInfo[filmId];
        fInfo.fundType = _fundType;
        fInfo.noVote = _noVote;
        fInfo.studio = msg.sender;
        fInfo.status = Helper.Status.LISTED;

        proposalFilmIds.push(filmId);
        userFilmProposalIds[msg.sender].push(filmId);

        emit FilmProposalCreated(filmId, _noVote, _fundType, msg.sender, block.timestamp);
    }
    function proposalFilmUpdate(
        uint256 _filmId, 
        string memory _title,
        string memory _description,
        uint256[] memory _sharePercents,
        address[] memory _studioPayees,
        uint256 _raiseAmount,
        uint256 _fundPeriod,
        uint256 _enableClaimer
    ) public {                
        require(_studioPayees.length > 0, 'proposalUpdate: empty payees');
        require(_studioPayees.length == _sharePercents.length, 'proposalUpdate: invalid share percent');

        IVabbleDAO.Film storage fInfo = filmInfo[_filmId];
        if(fInfo.fundType > 0) {            
            require(_fundPeriod > 0, 'proposalUpdate: invalid fund period');
            require(_raiseAmount > IProperty(DAO_PROPERTY).minDepositAmount(), 'proposalUpdate: invalid raise amount');
        }

        uint256 totalPercent = 0;
        if(_studioPayees.length == 1) totalPercent = _sharePercents[0];
        else {
            for(uint256 i = 0; i < _studioPayees.length; i++) {
                totalPercent += _sharePercents[i];
            }
        }
        require(totalPercent == 1e10, 'proposalUpdate: total percent should be 100%');
        
        require(fInfo.status == Helper.Status.LISTED, 'proposalUpdate: Not listed');
        require(fInfo.studio == msg.sender, 'proposalUpdate: not film owner');

        fInfo.title = _title;
        fInfo.description = _description;
        fInfo.sharePercents = _sharePercents;
        fInfo.studioPayees = _studioPayees;    
        fInfo.raiseAmount = _raiseAmount;
        fInfo.fundPeriod = _fundPeriod;
        fInfo.enableClaimer = _enableClaimer;
        fInfo.pCreateTime = block.timestamp;
        fInfo.studio = msg.sender;
        fInfo.status = Helper.Status.UPDATED;

        IStakingPool(STAKING_POOL).updateProposalCreatedTimeList(block.timestamp); // add timestap to array for calculating rewards

        // If proposal is for fund, update "lastfundProposalCreateTime"
        if(fInfo.fundType > 0) {
            IStakingPool(STAKING_POOL).updateLastfundProposalCreateTime(block.timestamp);

            if(fInfo.noVote == 1) {
                fInfo.status = Helper.Status.APPROVED_FUNDING;
                fInfo.pApproveTime = block.timestamp;
                approvedFundingFilmIds.push(_filmId);
                userApprovedFilmIds[msg.sender].push(_filmId);
            } 
        }       

        emit FilmProposalUpdated(_filmId, fInfo.fundType, msg.sender, block.timestamp);     
    }

    /// @notice Check if proposal fee transferred from studio to stakingPool
    // Get expected VAB amount from UniswapV2 and then Transfer VAB: user(studio) -> stakingPool.
    function __paidFee(address _dToken, uint256 _noVote) private {    
        uint256 feeAmount = IProperty(DAO_PROPERTY).proposalFeeAmount(); // in cash(usdc)
        if(_noVote == 1) feeAmount = IProperty(DAO_PROPERTY).proposalFeeAmount() * 2;
        
        uint256 expectTokenAmount = feeAmount;
        if(_dToken != IOwnablee(OWNABLE).USDC_TOKEN()) {
            expectTokenAmount = IUniHelper(UNI_HELPER).expectedAmount(feeAmount, IOwnablee(OWNABLE).USDC_TOKEN(), _dToken);
        }

        if(_dToken == address(0)) {
            require(msg.value >= expectTokenAmount, "paidFee: Insufficient paid");
            if (msg.value > expectTokenAmount) {
                Helper.safeTransferETH(msg.sender, msg.value - expectTokenAmount);
            }
            // Send ETH from this contract to UNI_HELPER contract
            Helper.safeTransferETH(UNI_HELPER, expectTokenAmount);
        } else {
            Helper.safeTransferFrom(_dToken, msg.sender, address(this), expectTokenAmount);
            if(IERC20(_dToken).allowance(address(this), UNI_HELPER) == 0) {
                Helper.safeApprove(_dToken, UNI_HELPER, IERC20(_dToken).totalSupply());
            }
        }                
        
        address vabToken = IOwnablee(OWNABLE).PAYOUT_TOKEN();
        bytes memory swapArgs = abi.encode(expectTokenAmount, _dToken, vabToken);
        uint256 vabAmount = IUniHelper(UNI_HELPER).swapAsset(swapArgs);    
        
        if(IERC20(vabToken).allowance(address(this), STAKING_POOL) == 0) {
            Helper.safeApprove(vabToken, STAKING_POOL, IERC20(vabToken).totalSupply());
        }  
        IStakingPool(STAKING_POOL).addRewardToPool(vabAmount);
    } 

    /// @notice Approve a film for funding/listing from vote contract
    function approveFilmByVote(uint256 _filmId, uint256 _flag) external onlyVote {
        require(_filmId > 0, "approveFilmByVote: Invalid filmId"); 

        filmInfo[_filmId].pApproveTime = block.timestamp;

        (, , uint256 fundType) = getFilmFund(_filmId);
        if(_flag == 0) {
            if(fundType > 0) { // in case of fund film
                filmInfo[_filmId].status = Helper.Status.APPROVED_FUNDING;
                approvedFundingFilmIds.push(_filmId);
            } else {
                filmInfo[_filmId].status = Helper.Status.APPROVED_LISTING;    
                approvedListingFilmIds.push(_filmId);
            }        
            address studioA = filmInfo[_filmId].studio;
            userApprovedFilmIds[studioA].push(_filmId);
        } else {
            filmInfo[_filmId].status = Helper.Status.REJECTED;
        } 
    }

    /// @notice onlyStudio update film fund period
    function updateFilmFundPeriod(uint256 _filmId, uint256 _fundPeriod) external nonReentrant {
        require(msg.sender == filmInfo[_filmId].studio, "updateFundPeriod: not film owner");
        require(filmInfo[_filmId].fundType > 0, "updateFundPeriod: not fund film");

        filmInfo[_filmId].fundPeriod = _fundPeriod;
        
        emit FilmFundPeriodUpdated(_filmId, msg.sender, _fundPeriod, block.timestamp);
    }   

    /// @notice Set final films for a customer with watched 
    // Auditor call this function per month
    function setFinalFilms(        
        address[] memory _users,
        bytes32[] memory _kData,
        uint256[] memory _payouts // VAB to payees based on share(%) and watch(%) from offchain
    ) external onlyAuditor nonReentrant {
        // require(block.timestamp - lastRunTime >= 30 days, "Allow update monthly");

        require(_kData.length > 0 && _kData.length == _payouts.length, "setFinalFilms: bad length");
        require(_users.length == _payouts.length, "setFinalFilms: bad user length");

        uint256[] memory idList = new uint256[](_kData.length);
        for(uint256 i = 0; i < _kData.length; i++) {     
            idList[i] = __setFinalFilm(_users[i], _kData[i], _payouts[i]);
        }

        // TODO  ==================================================
        __finalPaymentProcess(idList);
        
        lastRunTime = block.timestamp;
    }
    
    function __setFinalFilm(
        address _user, 
        bytes32 _kData, 
        uint256 _payout  
    ) private returns (uint256) {     
        uint256 filmId = 0;
        for(uint256 i = 1; i <= filmCount.current(); i++) {   
            if(keccak256(abi.encodePacked(i, _user)) == _kData) filmId = i;
        }

        IVabbleDAO.Film memory fInfo = filmInfo[filmId];
        require(fInfo.status == Helper.Status.APPROVED_LISTING, "Not approved listing film");
                  
        uint256 userVAB = IStakingPool(STAKING_POOL).getRentVABAmount(_user);
        require(_payout > 0 && userVAB >= _payout, "setFinalFilm: insufficient balance");

        IStakingPool(STAKING_POOL).sendVAB(_user, address(this), _payout);
        finalVABPayout[filmId] += _payout;

        //======= Process of Revenue
        uint256 nftCountOwned;
        uint256[] memory nftList = IFactoryFilmNFT(FILM_NFT_FACTORY).getFilmTokenIdList(filmId);
        for(uint256 i = 0; i < nftList.length; i++) {
            if(IERC721(FILM_NFT_FACTORY).ownerOf(nftList[i]) == _user) nftCountOwned += 1;
        }        

        ( , , , , uint256 revenuePercent, ,) = IFactoryFilmNFT(FILM_NFT_FACTORY).getMintInfo(filmId);
        uint256 revenueAmount = _payout * (revenuePercent / 1e10) * nftCountOwned;
        if(_payout >= revenueAmount && revenueAmount > 0) {
            // Transfer revenue amount to user if user fund to this film throughout NFT mint
            IStakingPool(STAKING_POOL).sendRevenueVAB(_user, revenueAmount);
        }        

        userFinalFilmIds[_user].push(filmId);

        return filmId;
    }     

    function __finalPaymentProcess(uint256[] memory _filmIds) private {

        IVabbleDAO.Film memory fInfo;
        uint256 _id;

        for(uint256 p = 0; p < _filmIds.length; p++) {
            _id = _filmIds[p];
            if(finalVABPayout[_id] == 0) continue;

            fInfo = filmInfo[_id];
            for(uint256 k = 0; k < fInfo.studioPayees.length; k++) {
                uint256 shareAmount = finalVABPayout[_id] * fInfo.sharePercents[k] / 1e10;
                Helper.safeTransfer(IOwnablee(OWNABLE).PAYOUT_TOKEN(), fInfo.studioPayees[k], shareAmount);
            }

            finalVABPayout[_id] = 0;
        }
    }
    /// @dev For transferring to Studio, Get share amount based on share percent
    function __getShareAmount(
        uint256 _payout, 
        uint256 _filmId, 
        uint256 _k
    ) private view returns(uint256) {
        return _payout * filmInfo[_filmId].sharePercents[_k] / 1e10;
    }

    /// @notice Get film status based on Id
    function getFilmStatus(uint256 _filmId) external view returns (Helper.Status status_) {
        status_ = filmInfo[_filmId].status;
    }

    /// @notice Get film owner(studio) based on Id
    function getFilmOwner(uint256 _filmId) external view returns (address owner_) {
        owner_ = filmInfo[_filmId].studio;
    }

    /// @notice Get film fund info based on Id
    function getFilmFund(uint256 _filmId) public view 
    returns (
        uint256 raiseAmount_, 
        uint256 fundPeriod_, 
        uint256 fundType_
    ) {
        raiseAmount_ = filmInfo[_filmId].raiseAmount;
        fundPeriod_ = filmInfo[_filmId].fundPeriod;
        fundType_ = filmInfo[_filmId].fundType;
    }

    /// @notice Get film fund info based on Id
    function getFilmShare(uint256 _filmId) external view 
    returns (
        uint256[] memory sharePercents_, 
        address[] memory studioPayees_
    ) {
        sharePercents_ = filmInfo[_filmId].sharePercents;
        studioPayees_ = filmInfo[_filmId].studioPayees;
    }

    /// @notice Get film proposal created time based on Id
    function getFilmProposalTime(uint256 _filmId) external view returns (uint256 cTime_, uint256 aTime_) {
        cTime_ = filmInfo[_filmId].pCreateTime;
        aTime_ = filmInfo[_filmId].pApproveTime;
    }

    /// @notice Get enableClaimer based on Id
    function isEnabledClaimer(uint256 _filmId) external view returns (bool enable_) {
        if(filmInfo[_filmId].enableClaimer == 1) enable_ = true;
        else enable_ = false;
    }
    
    /// @notice Set enableClaimer based on Id by studio
    function updateEnabledClaimer(uint256 _filmId, uint256 _enable) external {
        require(filmInfo[_filmId].studio == msg.sender, "updateEnableClaimer: not film owner");

        filmInfo[_filmId].enableClaimer = _enable;
    }

    /// @notice Get film Ids
    function getFilmIds(uint256 _flag) external view returns (uint256[] memory list_) {        
        if(_flag == 1) list_ = proposalFilmIds;
        else if(_flag == 2) list_ = approvedListingFilmIds;        
        else if(_flag == 3) list_ = approvedFundingFilmIds;
    }

    function getUserFilmIds(uint256 _flag, address _user) external view returns (uint256[] memory list_) {        
        if(_flag == 1) list_ = userFinalFilmIds[_user];      
        else if(_flag == 2) list_ = userFilmProposalIds[_user];
        else if(_flag == 3) list_ = userApprovedFilmIds[_user];
    }

    function getUserFilmListForMigrate(address _user) external view returns (IVabbleDAO.Film[] memory filmList_) {   
        IVabbleDAO.Film memory fInfo;
        uint256[] memory ids = userApprovedFilmIds[_user];
        require(ids.length > 0, "migrate: no film");

        filmList_ = new IVabbleDAO.Film[](ids.length);
        for(uint256 i = 0; i < ids.length; i++) {             
            fInfo = filmInfo[ids[i]];
            require(fInfo.studio == _user, "migrate: not film owner");

            if(fInfo.status == Helper.Status.APPROVED_FUNDING || fInfo.status == Helper.Status.APPROVED_LISTING) {
                filmList_[i] = fInfo;
            }
        }
    }
}
