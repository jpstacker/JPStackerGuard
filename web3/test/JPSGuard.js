const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("JPSGuard", function () {
  let jpsGuard, owner, manager, user1, user2;
  const initialURI = "https://example.com/service";
  const txFee = 10; // 10%

  before(async function () {
    [owner, manager, user1, user2] = await ethers.getSigners();
  });

  beforeEach(async function () {
    const JPSGuardFactory = await ethers.getContractFactory("JPSGuard");
    jpsGuard = await JPSGuardFactory.deploy(initialURI, txFee);
    await jpsGuard.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await jpsGuard.owner()).to.equal(owner.address);
    });

    it("Should register initial public service", async function () {
      const service = await jpsGuard.services(1);
      expect(service.uri).to.equal(initialURI);
      expect(service.manager).to.equal(owner.address);
      expect(service.status).to.equal(0); // Public
      expect(service.active).to.be.true;
    });

    it("Should set the correct transaction fee", async function () {
      expect(await jpsGuard.i_Transaction_Fee()).to.equal(txFee);
    });
  });

  describe("Service Registration", function () {
    it("Should allow owner to register a new service", async () => {
      const newServiceURI = "https://example.com/new-service";
      await expect(
        jpsGuard.connect(owner).registerService(
          newServiceURI,
          manager.address,
          ethers.parseEther("1"),
          100,
          0, // Public
          true,
          true
        )
      ).to.emit(jpsGuard, "ServiceRegistered");

      const service = await jpsGuard.services(2);
      expect(service.uri).to.equal(newServiceURI);
      expect(service.manager).to.equal(manager.address);
      expect(service.price).to.equal(ethers.parseEther("1"));
      expect(service.remainingTokens).to.equal(100);
      expect(service.status).to.equal(0); // Public
      expect(service.isLimitedToken).to.be.true;
      expect(service.active).to.be.true;
    });

    it("Should not allow non-owner to register a service", async function () {
      await expect(
        jpsGuard.connect(user1).registerService(
          "https://example.com/new-service",
          manager.address,
          ethers.parseEther("1"),
          100,
          0, // Public
          true,
          true
        )
      ).to.be.revertedWithCustomError(jpsGuard, "OwnableUnauthorizedAccount");
    });

    it("Should not allow empty URI when registering service", async function () {
      await expect(
        jpsGuard.connect(owner).registerService(
          "",
          manager.address,
          ethers.parseEther("1"),
          100,
          0, // Public
          true,
          true
        )
      ).to.be.revertedWithCustomError(jpsGuard, "JPSG_EmptyURI");
    });
  });

  describe("Token Minting", function () {
    describe("Public Tokens", function () {
      beforeEach(async function () {
        // Register a public service
        await jpsGuard.connect(owner).registerService(
          "https://example.com/public-service",
          manager.address,
          0,
          100,
          0, // Public
          true,
          true
        );
      });

      it("Should allow anyone to mint public token", async function () {
        await expect(jpsGuard.connect(user1).mintPublicToken(user1.address, 2))
          .to.emit(jpsGuard, "TokenMinted")
          .withArgs(user1.address, 1);

        await expect(jpsGuard.connect(user1).mintPublicToken(user2.address, 2))
          .to.emit(jpsGuard, "TokenMinted")
          .withArgs(user2.address, 2);

        expect(await jpsGuard.ownerOf(1)).to.equal(user1.address);
        expect(await jpsGuard.isValid(1)).to.be.true;
      });

      it("Should not allow minting for inactive service", async function () {
        // Deactivate service
        await jpsGuard.connect(manager).updateServiceActive(2, false);

        await expect(
          jpsGuard.connect(user1).mintPublicToken(user1.address, 2)
        ).to.be.revertedWithCustomError(jpsGuard, "JPSG_InactiveService");
      });

      it("Should not allow minting if token limit reached", async function () {
        // Set remaining tokens to 1
        await jpsGuard.connect(manager).updateServiceRemainingTokens(2, 1);

        // First mint should succeed
        await jpsGuard.connect(user1).mintPublicToken(user1.address, 2);

        // Second mint should fail
        await expect(
          jpsGuard.connect(user2).mintPublicToken(user2.address, 2)
        ).to.be.revertedWithCustomError(jpsGuard, "JPSG_TokenLimitExceeded");
      });
    });

    describe("Private Tokens", function () {
      beforeEach(async function () {
        // Register a private service
        await jpsGuard.connect(owner).registerService(
          "https://example.com/private-service",
          manager.address,
          0,
          100,
          1, // Private
          true,
          true
        );
      });

      it("Should allow owner to mint private token", async function () {
        await expect(jpsGuard.connect(owner).mintPrivateToken(user1.address, 2))
          .to.emit(jpsGuard, "TokenMinted")
          .withArgs(user1.address, 1);

        expect(await jpsGuard.ownerOf(1)).to.equal(user1.address);
      });

      it("Should not allow non-owner to mint private token", async function () {
        await expect(
          jpsGuard.connect(user1).mintPrivateToken(user1.address, 2)
        ).to.be.revertedWithCustomError(jpsGuard, "OwnableUnauthorizedAccount");
      });
    });

    describe("Service Tokens", function () {
      beforeEach(async function () {
        // Register a service-specific service
        await jpsGuard.connect(owner).registerService(
          "https://example.com/service-specific",
          manager.address,
          0,
          100,
          2, // Service
          true,
          true
        );
      });

      it("Should allow manager to mint service token", async function () {
        await expect(
          jpsGuard.connect(manager).mintServiceToken(user1.address, 2)
        )
          .to.emit(jpsGuard, "TokenMinted")
          .withArgs(user1.address, 1);

        expect(await jpsGuard.ownerOf(1)).to.equal(user1.address);
      });

      it("Should not allow non-manager to mint service token", async function () {
        await expect(
          jpsGuard.connect(user1).mintServiceToken(user1.address, 2)
        ).to.be.revertedWithCustomError(jpsGuard, "JPSG_NotManager");
      });
    });

    describe("Paid Tokens", function () {
      const servicePrice = ethers.parseEther("1");

      beforeEach(async function () {
        // Register a paid service
        await jpsGuard.connect(owner).registerService(
          "https://example.com/paid-service",
          manager.address,
          servicePrice,
          100,
          3, // Paid
          true,
          true
        );
      });

      it("Should allow manager to mint paid token with correct payment", async function () {
        await expect(
          jpsGuard
            .connect(manager)
            .mintPaidToken(user1.address, 2, { value: servicePrice })
        )
          .to.emit(jpsGuard, "TokenMinted")
          .withArgs(user1.address, 1);

        expect(await jpsGuard.ownerOf(1)).to.equal(user1.address);
      });

      it("Should transfer correct amounts to manager and contract", async function () {
        // Get initial balances
        const managerBalBefore = await ethers.provider.getBalance(
          manager.address
        );
        const contractBalBefore = await ethers.provider.getBalance(
          await jpsGuard.getAddress()
        );

        // Send transaction and get receipt
        await jpsGuard
          .connect(user1)
          .mintPaidToken(user1.address, 2, { value: servicePrice });

        // Calculate expected values
        const txFeeAmount = (servicePrice * BigInt(txFee)) / 100n;
        const expectedManagerAmount = servicePrice - txFeeAmount;

        // Get new balances
        const managerBalAfter = await ethers.provider.getBalance(
          manager.address
        );
        const contractBalAfter = await ethers.provider.getBalance(
          await jpsGuard.getAddress()
        );

        // Calculate actual changes
        const managerReceived = managerBalAfter - managerBalBefore;
        const contractReceived = contractBalAfter - contractBalBefore;

        // Check fee distribution (within 0.1% tolerance for gas fluctuations)
        expect(managerReceived).to.be.closeTo(
          expectedManagerAmount,
          expectedManagerAmount / 1000n // 0.1% tolerance
        );

        expect(contractReceived).to.equal(txFeeAmount);
      });

      it("Should not allow insufficient payment", async function () {
        await expect(
          jpsGuard
            .connect(manager)
            .mintPaidToken(user1.address, 2, { value: servicePrice / 2n })
        ).to.be.revertedWithCustomError(jpsGuard, "JPSG_InsufficientFundsSent");
      });
    });

    describe("Whitelisted Tokens", function () {
      beforeEach(async function () {
        // Register a whitelisted service
        await jpsGuard.connect(owner).registerService(
          "https://example.com/whitelisted-service",
          manager.address,
          0,
          100,
          4, // Whitelisted
          true,
          true
        );

        // Whitelist user1
        await jpsGuard.connect(manager).updateWhitelist(user1.address, 2, true);
      });

      it("Should allow whitelisted user to mint token", async function () {
        await expect(
          jpsGuard.connect(user1).mintWhitelistedToken(user1.address, 2)
        )
          .to.emit(jpsGuard, "TokenMinted")
          .withArgs(user1.address, 1);

        expect(await jpsGuard.ownerOf(1)).to.equal(user1.address);
      });

      it("Should not allow non-whitelisted user to mint token", async function () {
        await expect(
          jpsGuard.connect(user2).mintWhitelistedToken(user2.address, 2)
        ).to.be.revertedWithCustomError(jpsGuard, "JPSG_NotWhitelisted");
      });
    });
  });

  describe("Token Management", function () {
    let tokenId;

    beforeEach(async function () {
      // Register a service and mint a token
      await jpsGuard.connect(owner).registerService(
        "https://example.com/test-service",
        manager.address,
        0,
        100,
        2, // Service
        true,
        true
      );

      await jpsGuard.connect(manager).mintServiceToken(user1.address, 2);
      tokenId = 1n;
    });

    it("Should return correct token URI", async function () {
      expect(await jpsGuard.tokenURI(tokenId)).to.equal(
        "https://example.com/test-service"
      );
    });

    it("Should allow manager to revoke token", async function () {
      await expect(
        jpsGuard.connect(manager).revokeToken(user1.address, tokenId)
      )
        .to.emit(jpsGuard, "Revoked")
        .withArgs(user1.address, tokenId);

      expect(await jpsGuard.isValid(tokenId)).to.be.false;
    });

    it("Should not allow revoking invalid token", async function () {
      await expect(
        jpsGuard.connect(manager).revokeToken(user1.address, 999)
      ).to.be.revertedWithCustomError(jpsGuard, "JPSG_NotManager");
    });

    it("Should not allow revoking token for wrong owner", async function () {
      await expect(
        jpsGuard.connect(manager).revokeToken(user2.address, tokenId)
      ).to.be.revertedWithCustomError(jpsGuard, "JPSG_NotTokenOwner");
    });
  });

  describe("Whitelist Management", function () {
    beforeEach(async function () {
      // Register a whitelisted service
      await jpsGuard.connect(owner).registerService(
        "https://example.com/whitelisted-service",
        manager.address,
        0,
        100,
        4, // Whitelisted
        true,
        true
      );
    });

    it("Should allow manager to update whitelist", async function () {
      await expect(
        jpsGuard.connect(manager).updateWhitelist(user1.address, 2, true)
      )
        .to.emit(jpsGuard, "WhitelistUpdated")
        .withArgs(user1.address, 2, true);

      expect(await jpsGuard.isWhitelisted(2, user1.address)).to.be.true;
    });

    it("Should allow manager to batch update whitelist", async function () {
      await jpsGuard
        .connect(manager)
        .updateWhitelistBatch([user1.address, user2.address], 2, true);

      expect(await jpsGuard.isWhitelisted(2, user1.address)).to.be.true;
      expect(await jpsGuard.isWhitelisted(2, user2.address)).to.be.true;

      await jpsGuard
        .connect(manager)
        .updateWhitelistBatch([user1.address, user2.address], 2, false);

      expect(await jpsGuard.isWhitelisted(2, user1.address)).to.be.false;
      expect(await jpsGuard.isWhitelisted(2, user2.address)).to.be.false;

      await jpsGuard
        .connect(manager)
        .updateWhitelistBatch([user1.address, user2.address], 2, true);

      expect(await jpsGuard.isWhitelisted(2, user1.address)).to.be.true;
      expect(await jpsGuard.isWhitelisted(2, user2.address)).to.be.true;
    });

    it("Should not allow non-manager to update whitelist", async function () {
      await expect(
        jpsGuard.connect(user1).updateWhitelist(user1.address, 2, true)
      ).to.be.revertedWithCustomError(jpsGuard, "JPSG_NotManager");
    });
  });

  describe("Service Management", function () {
    beforeEach(async function () {
      // Register a service
      await jpsGuard.connect(owner).registerService(
        "https://example.com/managed-service",
        manager.address,
        0,
        100,
        2, // Service
        true,
        true
      );
    });

    it("Should allow owner to update service manager", async function () {
      await jpsGuard.connect(owner).updateServiceManager(user1.address, 2);
      expect((await jpsGuard.services(2)).manager).to.equal(user1.address);
    });

    it("Should not allow non-owner to update service manager", async function () {
      await expect(
        jpsGuard.connect(manager).updateServiceManager(user1.address, 2)
      ).to.be.revertedWithCustomError(jpsGuard, "OwnableUnauthorizedAccount");
    });

    it("Should allow manager to update service URI", async function () {
      const newURI = "https://example.com/new-uri";
      await jpsGuard.connect(manager).updateServiceURI(newURI, 2);
      expect((await jpsGuard.services(2)).uri).to.equal(newURI);
    });

    it("Should not allow empty URI when updating", async function () {
      await expect(
        jpsGuard.connect(manager).updateServiceURI("", 2)
      ).to.be.revertedWithCustomError(jpsGuard, "JPSG_EmptyURI");
    });

    it("Should not allow non-manager to update service URI", async function () {
      await expect(
        jpsGuard.connect(user1).updateServiceURI("aaa", 2)
      ).to.be.revertedWithCustomError(jpsGuard, "JPSG_NotManager");
    });

    it("Should allow manager to update remaining tokens", async function () {
      await jpsGuard.connect(manager).updateServiceRemainingTokens(2, 50);
      expect((await jpsGuard.services(2)).remainingTokens).to.equal(50);
    });

    it("Should allow manager to update service active status", async function () {
      await jpsGuard.connect(manager).updateServiceActive(2, false);
      expect((await jpsGuard.services(2)).active).to.be.false;
    });

    it("Should allow manager to update service price", async function () {
      const newPrice = ethers.parseEther("0.5");
      await jpsGuard.connect(manager).updateServicePrice(2, newPrice);
      expect((await jpsGuard.services(2)).price).to.equal(newPrice);
    });
  });

  describe("Withdrawals", function () {
    const servicePrice = ethers.parseEther("1");

    beforeEach(async function () {
      // Register a paid service and mint a token to accumulate funds
      await jpsGuard.connect(owner).registerService(
        "https://example.com/paid-service",
        manager.address,
        servicePrice,
        100,
        3, // Paid
        true,
        true
      );

      await jpsGuard
        .connect(manager)
        .mintPaidToken(user1.address, 2, { value: servicePrice });
    });

    it("Should allow owner to withdraw contract balance", async function () {
      const contractBalBefore = await ethers.provider.getBalance(
        await jpsGuard.getAddress()
      );
      const ownerBalanceBefore = await ethers.provider.getBalance(
        owner.address
      );

      const tx = await jpsGuard.connect(owner).withdraw();
      const receipt = await tx.wait();
      const gasUsed = receipt.gasUsed * receipt.gasPrice;

      const contractBalAfter = await ethers.provider.getBalance(
        await jpsGuard.getAddress()
      );
      const ownerBalanceAfter = await ethers.provider.getBalance(owner.address);

      expect(contractBalAfter).to.equal(0);
      expect(ownerBalanceAfter).to.equal(
        ownerBalanceBefore + contractBalBefore - gasUsed
      );
    });

    it("Should not allow non-owner to withdraw", async function () {
      await expect(
        jpsGuard.connect(user1).withdraw()
      ).to.be.revertedWithCustomError(jpsGuard, "OwnableUnauthorizedAccount");
    });
  });

  describe("Utility Functions", function () {
    beforeEach(async function () {
      // Register a service and mint some tokens
      await jpsGuard.connect(owner).registerService(
        "https://example.com/test-service",
        manager.address,
        0,
        100,
        0, // Public
        true,
        true
      );

      // Mint 5 tokens to user1
      for (let i = 0; i < 5; i++) {
        await jpsGuard.connect(user1).mintPublicToken(user1.address, 2);
      }
    });

    it("Should fetch user token IDs with pagination", async function () {
      const page1 = await jpsGuard.fetchUserIDs(user1.address, 0, 2);
      expect(page1.length).to.equal(2);
      expect(page1[0]).to.equal(1);
      expect(page1[1]).to.equal(2);

      const page2 = await jpsGuard.fetchUserIDs(user1.address, 2, 2);
      expect(page2.length).to.equal(2);
      expect(page2[0]).to.equal(3);
      expect(page2[1]).to.equal(4);

      const page3 = await jpsGuard.fetchUserIDs(user1.address, 4, 2);
      expect(page3.length).to.equal(1);
      expect(page3[0]).to.equal(5);
    });
  });
});
