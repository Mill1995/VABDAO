const { expect } = require('chai');
const { ethers } = require('hardhat');
const { CONFIG } = require('../scripts/utils');

describe('Owner', function () {
  before(async function () {
    this.RentFilmFactory = await ethers.getContractFactory('RentFilm');
    this.MockERC20Factory = await ethers.getContractFactory('MockERC20');
    this.VoteFilmFactory = await ethers.getContractFactory('VoteFilm');

    this.signers = await ethers.getSigners();
    this.auditor = this.signers[0];
    this.newAuditor = this.signers[1];
  });

  beforeEach(async function () {
    
    this.vabContract = await (await this.MockERC20Factory.deploy('Mock Token', 'VAB')).deployed();
    this.voteConract = await (await this.VoteFilmFactory.deploy()).deployed();

    this.rentContract = await (
      await this.RentFilmFactory.deploy(
        CONFIG.daoFeeAddress,
        this.vabContract.address,
        this.voteConract.address
      )
    ).deployed();   
    
  });

  describe('Checking ownership', function () {
    it('Transfer ownership', async function () {
      expect(await this.rentContract.auditor()).to.be.equal(this.auditor.address);

      await this.rentContract.transferAuditor(this.newAuditor.address);
      
      expect(await this.rentContract.auditor()).to.be.equal(this.newAuditor.address);  
    });
  });
});