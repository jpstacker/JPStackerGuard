const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("JPSMarketplace Comprehensive Unit Tests", function () {
  let JPSMarketplace, marketplace, owner, user1, user2, user3, paymentToken;
  const BASE_PRICE = ethers.parseEther("1");
  const TOTAL_SUPPLY = 1000;
  const MAX_PER_WALLET = 10;

  // Deploy fresh contract before each test
  beforeEach(async function () {
    [owner, user1, user2, user3] = await ethers.getSigners();

    // Deploy mock ERC20 token for testing
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    paymentToken = await ERC20Mock.deploy("Mock Token", "MTK", ethers.parseEther("10000"));
    await paymentToken.waitForDeployment();

    // Deploy JPSMarketplace
    JPSMarketplace = await ethers.getContractFactory("JPSMarketplace");
    marketplace = await JPSMarketplace.deploy(
      BASE_PRICE,
      TOTAL_SUPPLY,
      MAX_PER_WALLET,
      owner.address,
      paymentToken.target
    );
    await marketplace.waitForDeployment();

    // Mint some tokens to user1 for testing
    await paymentToken.transfer(user1.address, ethers.parseEther("1000"));
    await paymentToken.connect(user1).approve(marketplace.target, ethers.parseEther("1000"));
  });

  describe("Deployment and Initialization", function () {
    it("should set correct initial parameters", async function () {
      expect(await marketplace.totalSupply()).to.equal(TOTAL_SUPPLY);
      expect(await marketplace.maxPerWallet()).to.equal(MAX_PER_WALLET);
      expect(await marketplace.feeRecipient()).to.equal(owner.address);
      expect(await marketplace.paymentToken()).to.equal(paymentToken.target);
      
      const pricingConfig = await marketplace.pricingConfig();
      expect(pricingConfig.basePrice).to.equal(BASE_PRICE);
      expect(pricingConfig.minPrice).to.equal(BASE_PRICE / BigInt(10));
      expect(pricingConfig.maxPrice).to.equal(BASE_PRICE * BigInt(10));
    });

    it("should set correct rarity multipliers", async function () {
      expect(await marketplace.rarityMultipliers(0)).to.equal(100); // Common
      expect(await marketplace.rarityMultipliers(1)).to.equal(150); // Rare
      expect(await marketplace.rarityMultipliers(2)).to.equal(300); // Epic
      expect(await marketplace.rarityMultipliers(3)).to.equal(500); // Legendary
    });
  });

  describe("Dynamic Pricing", function () {
    it("should calculate initial price correctly", async function () {
      const commonPrice = await marketplace.getCurrentPrice(0);
      expect(commonPrice).to.be.closeTo(BASE_PRICE, ethers.parseEther("0.1"));
    });

    it("should increase price with demand", async function () {
      await marketplace.connect(user1).mintNFT(
        "uri1", "cat1", 0, 1000, // Common rarity, 10% royalty
        { value: ethers.parseEther("2") }
      );
      
      const newPrice = await marketplace.getCurrentPrice(0);
      expect(newPrice).to.be.above(BASE_PRICE);
    });

    it("should respect min and max price bounds", async function () {
      // Test min price
      await marketplace.updatePricingConfig(0, 0, 1000, 0); // Extreme decay
      await ethers.provider.send("evm_increaseTime", [86400 * 10]); // 10 days
      const minPrice = await marketplace.getCurrentPrice(0);
      expect(minPrice).to.equal(BASE_PRICE / BigInt(10));

      // Test max price
      await marketplace.updatePricingConfig(10000, 10000, 0, 10000);
      await marketplace.connect(user1).mintNFT(
        "uri2", "cat2", 3, 1000,
        { value: ethers.parseEther("20") }
      );
      const maxPrice = await marketplace.getCurrentPrice(3);
      expect(maxPrice).to.be.lte(BASE_PRICE * BigInt(10));
    });
  });

  describe("Minting Functionality", function () {
    it("should mint NFT successfully", async function () {
      await expect(marketplace.connect(user1).mintNFT(
        "uri1", "cat1", 1, 1000,
        { value: ethers.parseEther("2") }
      ))
        .to.emit(marketplace, "NFTMinted")
        .withArgs(1, user1.address, ethers.parseEther("1.5"), 1);

      const tokenData = await marketplace.tokenData(1);
      expect(tokenData.rarity).to.equal(1);
      expect(tokenData.royaltyPercentage).to.equal(1000);
      expect(await marketplace.ownerOf(1)).to.equal(user1.address);
    });

    it("should reject insufficient payment", async function () {
      await expect(marketplace.connect(user1).mintNFT(
        "uri1", "cat1", 0, 1000,
        { value: ethers.parseEther("0.5") }
      )).to.be.revertedWithCustomError(marketplace, "JPSM_InsufficientPayment");
    });

    it("should enforce max per wallet", async function () {
      for (let i = 0; i < MAX_PER_WALLET; i++) {
        await marketplace.connect(user1).mintNFT(
          `uri${i}`, "cat1", 0, 1000,
          { value: ethers.parseEther("2") }
        );
      }
      
      await expect(marketplace.connect(user1).mintNFT(
        "uri11", "cat1", 0, 1000,
        { value: ethers.parseEther("2") }
      )).to.be.revertedWithCustomError(marketplace, "JPSM_WalletLimitReached");
    });

    it("should enforce total supply", async function () {
      await marketplace.updatePricingConfig(0, 0, 0, 0); // Disable price increase
      
      for (let i = 0; i < TOTAL_SUPPLY; i++) {
        await marketplace.connect(user1).mintNFT(
          `uri${i}`, "cat1", 0, 1000,
          { value: ethers.parseEther("2") }
        );
      }
      
      await expect(marketplace.connect(user1).mintNFT(
        "uri1001", "cat1", 0, 1000,
        { value: ethers.parseEther("2") }
      )).to.be.revertedWithCustomError(marketplace, "JPSM_SupplyExhausted");
    });
  });

  describe("Marketplace Listings", function () {
    beforeEach(async function () {
      await marketplace.connect(user1).mintNFT(
        "uri1", "cat1", 0, 1000,
        { value: ethers.parseEther("2") }
      );
      await marketplace.connect(user1).approve(marketplace.target, 1);
    });

    it("should list NFT successfully", async function () {
      await expect(marketplace.connect(user1).listNFT(1, ethers.parseEther("2"), false, 86400))
        .to.emit(marketplace, "Listed")
        .withArgs(1, ethers.parseEther("2"), user1.address);

      const listing = await marketplace.listings(1);
      expect(listing.active).to.be.true;
      expect(listing.price).to.equal(ethers.parseEther("2"));
    });

    it("should allow purchase with ETH", async function () {
      await marketplace.connect(user1).listNFT(1, ethers.parseEther("2"), false, 86400);
      
      const sellerBalanceBefore = await ethers.provider.getBalance(user1.address);
      await expect(marketplace.connect(user2).buyNFT(1, false, { value: ethers.parseEther("2") }))
        .to.emit(marketplace, "Purchased")
        .withArgs(1, user2.address, ethers.parseEther("2"));

      const sellerBalanceAfter = await ethers.provider.getBalance(user1.address);
      expect(await marketplace.ownerOf(1)).to.equal(user2.address);
      expect(sellerBalanceAfter).to.be.above(sellerBalanceBefore);
    });

    it("should allow purchase with ERC20", async function () {
      await marketplace.connect(user1).listNFT(1, ethers.parseEther("2"), true, 86400);
      await paymentToken.transfer(user2.address, ethers.parseEther("10"));
      await paymentToken.connect(user2).approve(marketplace.target, ethers.parseEther("10"));

      await expect(marketplace.connect(user2).buyNFT(1, true))
        .to.emit(marketplace, "Purchased");
    });
  });

  describe("Auction Functionality", function () {
    beforeEach(async function () {
      await marketplace.connect(user1).mintNFT(
        "uri1", "cat1", 0, 1000,
        { value: ethers.parseEther("2") }
      );
      await marketplace.connect(user1).approve(marketplace.target, 1);
    });

    it("should start auction successfully", async function () {
      await expect(marketplace.connect(user1).startAuction(
        1,
        ethers.parseEther("1"),
        86400,
        false,
        300
      )).to.emit(marketplace, "AuctionStarted");
    });

    it("should handle bidding correctly", async function () {
      await marketplace.connect(user1).startAuction(1, ethers.parseEther("1"), 86400, false, 300);
      
      await expect(marketplace.connect(user2).placeBid(1, false, { value: ethers.parseEther("2") }))
        .to.emit(marketplace, "BidPlaced")
        .withArgs(1, user2.address, ethers.parseEther("2"));

      const auction = await marketplace.auctions(1);
      expect(auction.highestBidder).to.equal(user2.address);
      expect(auction.highestBid).to.equal(ethers.parseEther("2"));
    });

    it("should extend auction on late bid", async function () {
      await marketplace.connect(user1).startAuction(1, ethers.parseEther("1"), 600, false, 300);
      await ethers.provider.send("evm_increaseTime", [550]);
      
      await marketplace.connect(user2).placeBid(1, false, { value: ethers.parseEther("2") });
      const auction = await marketplace.auctions(1);
      expect(auction.duration).to.equal(900);
    });

    it("should end auction and transfer NFT", async function () {
      await marketplace.connect(user1).startAuction(1, ethers.parseEther("1"), 600, false, 300);
      await marketplace.connect(user2).placeBid(1, false, { value: ethers.parseEther("2") });
      await ethers.provider.send("evm_increaseTime", [700]);
      
      await expect(marketplace.endAuction(1))
        .to.emit(marketplace, "AuctionEnded")
        .withArgs(1, user2.address, ethers.parseEther("2"));
      
      expect(await marketplace.ownerOf(1)).to.equal(user2.address);
    });
  });

  describe("Admin Functions", function () {
    it("should update fee correctly", async function () {
      await marketplace.updateFee(500); // 5%
      expect(await marketplace.marketplaceFee()).to.equal(500);
    });

    it("should reject high fee", async function () {
      await expect(marketplace.updateFee(1500))
        .to.be.revertedWithCustomError(marketplace, "JPSM_InvalidParameters");
    });

    it("should pause and unpause", async function () {
      await marketplace.pause();
      await expect(marketplace.connect(user1).mintNFT(
        "uri1", "cat1", 0, 1000,
        { value: ethers.parseEther("2") }
      )).to.be.revertedWithCustomError(marketplace, "EnforcedPause");

      await marketplace.unpause();
      await marketplace.connect(user1).mintNFT(
        "uri1", "cat1", 0, 1000,
        { value: ethers.parseEther("2") }
      );
    });
  });

  describe("Edge Cases and Security", function () {
    it("should prevent reentrancy", async function () {
      // Deploy malicious contract
      const MaliciousBuyer = await ethers.getContractFactory("MaliciousBuyer");
      const malicious = await MaliciousBuyer.deploy(marketplace.target);
      
      await marketplace.connect(user1).mintNFT(
        "uri1", "cat1", 0, 1000,
        { value: ethers.parseEther("2") }
      );
      await marketplace.connect(user1).approve(marketplace.target, 1);
      await marketplace.connect(user1).listNFT(1, ethers.parseEther("1"), false, 86400);
      
      await expect(malicious.attack({ value: ethers.parseEther("1") }))
        .to.be.revertedWithCustomError(marketplace, "ReentrancyGuardReentrantCall");
    });

    it("should handle zero address checks", async function () {
      await expect(JPSMarketplace.deploy(
        BASE_PRICE,
        TOTAL_SUPPLY,
        MAX_PER_WALLET,
        ethers.ZeroAddress,
        paymentToken.target
      )).to.not.be.reverted; // Should handle zero address gracefully
    });
  });
});

// Mock ERC20 contract for testing
const ERC20MockArtifact = `
contract ERC20Mock {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        totalSupply = _initialSupply;
        balanceOf[msg.sender] = _initialSupply;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
}
`;

// Malicious contract for reentrancy testing
const MaliciousBuyerArtifact = `
contract MaliciousBuyer {
    JPSMarketplace public marketplace;
    bool public attacking;

    constructor(address _marketplace) {
        marketplace = JPSMarketplace(_marketplace);
    }

    function attack() external payable {
        attacking = true;
        marketplace.buyNFT(1, false);
    }

    receive() external payable {
        if (attacking) {
            marketplace.buyNFT(1, false);
        }
    }
}
`;

before(async () => {
  await ethers.provider.send("evm_setAutomine", [true]);
  await ethers.compile(ERC20MockArtifact, { contractName: "ERC20Mock" });
  await ethers.compile(MaliciousBuyerArtifact, { contractName: "MaliciousBuyer" });
});