// const { expect } = require("chai");
// const { ethers } = require("hardhat");
// const { time } = require("@nomicfoundation/hardhat-network-helpers");

// describe("JPStaking Contract", function () {
//   let JPStaking, jpStaking, owner, addr1, addr2, nftContract;
//   const TOTAL_SUPPLY = ethers.parseEther("1000000000"); // 1B tokens
//   const ICO_ALLOCATION = ethers.parseEther("400000000"); // 400M tokens
//   const MIN_CONTRIBUTION = ethers.parseEther("0.1");
//   const MAX_CONTRIBUTION = ethers.parseEther("100");

//   beforeEach(async function () {
//     // Deploy a mock ERC721 contract for NFT functionality
//     const NFT = await ethers.getContractFactory("ERC721Mock");
//     nftContract = await NFT.deploy("TestNFT", "TNFT");
//     await nftContract.waitForDeployment();

//     // Deploy JPStaking contract
//     JPStaking = await ethers.getContractFactory("JPStaking");
//     [owner, addr1, addr2] = await ethers.getSigners();
//     jpStaking = await JPStaking.deploy(await nftContract.getAddress());
//     await jpStaking.waitForDeployment();

//     // Mint an NFT to addr1 for testing NFT boost
//     await nftContract.mint(addr1.address, 1);
//   });

//   // --- ICO Tests ---
//   describe("ICO Functionality", function () {
//     it("Should allow contribution within limits", async function () {
//       const contribution = ethers.parseEther("1");
//       await jpStaking.connect(addr1).contribute({ value: contribution });
//       const tokens = contribution * BigInt(10**18) / ethers.parseEther("0.0001");
//       expect(await jpStaking.balanceOf(addr1.address)).to.equal(tokens);
//       expect(await jpStaking.totalRaised()).to.equal(tokens);
//       expect(await jpStaking.totalParticipants()).to.equal(1);
//     });

//     it("Should reject contribution below minimum", async function () {
//       await expect(
//         jpStaking.connect(addr1).contribute({ value: ethers.parseEther("0.01") })
//       ).to.be.revertedWith("Invalid contribution");
//     });

//     it("Should reject contribution after ICO ends", async function () {
//       await jpStaking.connect(owner).endICO();
//       await expect(
//         jpStaking.connect(addr1).contribute({ value: MIN_CONTRIBUTION })
//       ).to.be.revertedWith("ICO not active");
//     });

//     it("Should burn unsold tokens when ICO ends", async function () {
//       await jpStaking.connect(owner).endICO();
//       const expectedBurn = ICO_ALLOCATION - (await jpStaking.totalRaised());
//       expect(await jpStaking.balanceOf(await jpStaking.getAddress())).to.equal(TOTAL_SUPPLY - expectedBurn);
//     });
//   });

//   // --- Staking Tests ---
//   describe("Staking Functionality", function () {
//     beforeEach(async function () {
//       // Transfer some tokens to addr1 for staking
//       await jpStaking.connect(owner).transfer(addr1.address, ethers.parseEther("1000000"));
//     });

//     it("Should allow staking with valid amount and lock period", async function () {
//       const stakeAmount = ethers.parseEther("1000");
//       const lockPeriod = 30 * 24 * 60 * 60; // 30 days in seconds
//       await jpStaking.connect(addr1).stake(stakeAmount, lockPeriod, 0);

//       const stakes = await jpStaking.getUserStakes(addr1.address);
//       expect(stakes.length).to.equal(1);
//       expect(stakes[0].amount).to.equal(stakeAmount);
//       expect(stakes[0].tier).to.equal(0); // Bronze tier
//       expect(await jpStaking.totalStaked()).to.equal(stakeAmount);
//     });

//     it("Should apply NFT boost correctly", async function () {
//       const stakeAmount = ethers.parseEther("50000");
//       const lockPeriod = 90 * 24 * 60 * 60; // 90 days
//       await jpStaking.connect(addr1).stake(stakeAmount, lockPeriod, 1); // Using NFT ID 1
//       const stakes = await jpStaking.getUserStakes(addr1.address);
//       expect(stakes[0].nftBoostId).to.equal(1);
//       expect(stakes[0].tier).to.equal(2); // Gold tier
//     });

//     it("Should reject staking with insufficient balance", async function () {
//       await expect(
//         jpStaking.connect(addr2).stake(ethers.parseEther("1000"), 30 * 24 * 60 * 60, 0！”

//       ).to.be.revertedWith("Insufficient balance");
//     });
//   });

//   // --- Reward Tests ---
//   describe("Reward Calculation and Claiming", function () {
//     beforeEach(async function () {
//       await jpStaking.connect(owner).transfer(addr1.address, ethers.parseEther("100000"));
//       await jpStaking.connect(addr1).stake(ethers.parseEther("50000"), 90 * 24 * 60 * 60, 1);
//     });

//     it("Should calculate rewards correctly", async function () {
//       await time.increase(30 * 24 * 60 * 60); // Fast forward 30 days
//       const reward = await jpStaking.getTotalRewards(addr1.address);
//       expect(reward).to.be.gt(0);
//     });

//     it("Should allow claiming rewards", async function () {
//       await time.increase(30 * 24 * 60 * 60);
//       const initialBalance = await jpStaking.balanceOf(addr1.address);
//       await jpStaking.connect(addr1).claimRewards();
//       const newBalance = await jpStaking.balanceOf(addr1.address);
//       expect(newBalance).to.be.gt(initialBalance);
//     });
//   });

//   // --- Unstaking Tests ---
//   describe("Unstaking Functionality", function () {
//     beforeEach(async function () {
//       await jpStaking.connect(owner).transfer(addr1.address, ethers.parseEther("10000"));
//       await jpStaking.connect(addr1).stake(ethers.parseEther("1000"), 30 * 24 * 60 * 60, 0);
//     });

//     it("Should allow unstaking after lock period", async function () {
//       await time.increase(31 * 24 * 60 * 60);
//       const initialBalance = await jpStaking.balanceOf(addr1.address);
//       await jpStaking.connect(addr1).unstake(0);
//       const newBalance = await jpStaking.balanceOf(addr1.address);
//       expect(newBalance).to.be.gt(initialBalance);
//     });

//     it("Should reject unstaking before lock period", async function () {
//       await expect(
//         jpStaking.connect(addr1).unstake(0)
//       ).to.be.revertedWith("Lock period not ended");
//     });
//   });

//   // --- Governance Tests ---
//   describe("Governance Functionality", function () {
//     beforeEach(async function () {
//       await jpStaking.connect(owner).transfer(addr1.address, ethers.parseEther("20000"));
//       await jpStaking.connect(addr1).stake(ethers.parseEther("15000"), 30 * 24 * 60 * 60, 0);
//     });

//     it("Should create a proposal", async function () {
//       await jpStaking.connect(addr1).createProposal("Test Proposal");
//       const proposal = await jpStaking.proposals(1);
//       expect(proposal.description).to.equal("Test Proposal");
//       expect(proposal.proposer).to.equal(addr1.address);
//     });

//     it("Should allow voting", async function () {
//       await jpStaking.connect(addr1).createProposal("Test Proposal");
//       await jpStaking.connect(addr1).vote(1, true);
//       const proposal = await jpStaking.proposals(1);
//       expect(proposal.yesVotes).to.equal(ethers.parseEther("15000"));
//     });

//     it("Should execute proposal if approved", async function () {
//       await jpStaking.connect(addr1).createProposal("Test Proposal");
//       await jpStaking.connect(addr1).vote(1, true);
//       await time.increase(8 * 24 * 60 * 60); // After voting period
//       await jpStaking.connect(owner).executeProposal(1);
//       const proposal = await jpStaking.proposals(1);
//       expect(proposal.executed).to.be.true;
//     });
//   });

//   // --- Edge Cases ---
//   describe("Edge Cases", function () {
//     it("Should handle reward pool depletion gracefully", async function () {
//       await jpStaking.connect(owner).transfer(addr1.address, ethers.parseEther("100000"));
//       await jpStaking.connect(addr1).stake(ethers.parseEther("50000"), 90 * 24 * 60 * 60, 1);
//       await time.increase(365 * 24 * 60 * 60); // 1 year
//       await jpStaking.connect(owner).updateBaseRewardRate(0); // Deplete rewards artificially
//       await expect(jpStaking.connect(addr1).claimRewards()).to.be.revertedWith("No rewards to claim");
//     });
//   });
// });
