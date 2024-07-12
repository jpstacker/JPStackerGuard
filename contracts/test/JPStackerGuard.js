//
const { expect } = require("chai");
const { ethers } = require("hardhat");
const hre = require("hardhat");

//
require("chai").use(require("chai-as-promised")).should();

//
describe("JPSI Complete Unit Testing", async () => {
  let [owner, user, cnt] = ["", [], null];
  const zeroAddress = "0x0000000000000000000000000000000000000000";

  beforeEach(async () => {
    const [account01, ...account02] = await ethers.getSigners();
    owner = account01;
    user = account02;

    cnt = await hre.ethers.deployContract("JPStackerGuard", [
      "JPStacker Guard",
      "JPSG",
      "JPSI-URI",
    ]);
  });

  const isArr = (arr) => (Array.isArray(arr) ? arr : []);

  const getStringPara = (P1) =>
    isArr(P1)
      .map(({ name, type }) => `${name} ${type}`)
      .join(", ");

  const extractCntParams = (P00) => {
    let P01 = isArr(P00)?.filter(({ type }) => type === "function");
    P01 = P01.map(
      ({ name, inputs: P1, outputs: O1 }) =>
        `${name}(${getStringPara(P1)}) => (${getStringPara(O1)})`
    );
    P01.sort((a, b) => a.length - b.length);
    return P01;
  };

  //   const toNumber = (vl) => ethers.BigNumber.from(vl).toNumber();

  describe("JPSI Basic Functional Testing", () => {
    //
    it("Verifying common names", async () => {
      // console.log(extractCntParams(cnt.interface.fragments));
      expect(await cnt.name()).equal("JPStacker Guard");
      expect(await cnt.symbol()).equal("JPSG");
      expect(await cnt.owner()).equal(owner.address);
      await cnt.renounceOwnership();
      expect(await cnt.owner()).equal(zeroAddress);
    });
    //
    it("Running basic functions", async () => {
      expect(await cnt.owner()).equal(owner.address);
      expect(await cnt.emittedCount()).equal(0);
      expect(await cnt.holdersCount()).equal(0);
      expect(await cnt.serviceCount()).equal(1);

      expect(await cnt.isWhitelisted(1, user[0].address)).equal(false);
      const srv01 = await cnt.services(1);
      expect(srv01[0]).equal("JPSI-URI");
      expect(srv01[1]).equal(owner.address);
      expect(srv01[2]).equal(0);
      expect(srv01[4]).equal(0);
      expect(srv01[5]).equal(true);
    });
    //
    it("Running Intermidiate functions", async () => {
      expect(await cnt.isWhitelisted(1, user[0].address)).equal(false);
      await cnt.updateWhitelist(user[0].address, 1, true);
      expect(await cnt.isWhitelisted(1, user[0].address)).equal(true);
      await cnt.updateWhitelist(user[0].address, 2, true).should.be.rejected;
      expect(await cnt.isWhitelisted(1, user[1].address)).equal(false);
      expect(await cnt.isWhitelisted(1, user[2].address)).equal(false);
      expect(await cnt.isWhitelisted(1, user[3].address)).equal(false);
      await cnt.updateWhitelistBatch(
        [user[1].address, user[2].address, user[3].address],
        1,
        true
      );
      expect(await cnt.isWhitelisted(1, user[1].address)).equal(true);
      expect(await cnt.isWhitelisted(1, user[2].address)).equal(true);
      expect(await cnt.isWhitelisted(1, user[3].address)).equal(true);
    });
  });
});

// name() => ( string)
// owner() => ( address)
// symbol() => ( string)
// emittedCount() => ( uint256)
// holdersCount() => ( uint256)
// services( uint256) => (uri string, manager address, price uint256, tokenLimit uint64, status uint8, active bool)

// serviceCount() => ( uint256)
// isWhitelisted(uint256,  address) => ( bool)

// supportsInterface(interfaceId bytes4) => ( bool)
// renounceOwnership() => ()
// transferOwnership(newOwner address) => ()

// tokenIds( address) => ( uint256)
// tokenURI(tokenId uint256) => ( string)
// setTokenURI(tokenId uint256, tokenUri string) => ()

// tokenByIndex(index uint256) => ( uint256)
// tokensOfOwner(owner address) => (tokens uint256[])
// tokenOfOwnerByIndex(owner address, index uint256) => ( uint256)

// hasValid(owner address) => ( bool)
// isValid(tokenId uint256) => ( bool)
// balanceOf(owner address) => ( uint256)
// ownerOf(tokenId uint256) => ( address)

// mintPaidToken(user address, serviceId uint256) => ()
// mintPrivateToken(user address, serviceId uint256) => ()
// mintServiceToken(user address, serviceId uint256) => ()
// mintPublicOrWhitelistedToken(user address, serviceId uint256, _isPublic bool) => ()

// updatServiceManager(manager address, serviceId uint256) => ()
// updatServiceURI(uri string, serviceId uint256) => ()
// updatServiceActiveStatus(serviceId uint256, active bool) => ()
// updatServiceStatus(serviceId uint256, status uint8) => ()
// updatServicePrice(serviceId uint256, price uint256) => ()
// updatServiceTokenLimit(serviceId uint256, tokenLimit uint64) => ()

// updateWhitelist(user address, serviceId uint256, status bool) => ( bool)
// updateWhitelistBatch(_users address[], _tokenID uint256, _status bool) => ( bool)

// registerServiceToken(_uri string, _manager address, _price uint256, _tokenLimit uint64, _status uint8, _active bool) => (serviceId uint256)
