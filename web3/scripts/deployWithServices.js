const { ethers } = require("hardhat");

const deployWithServices =  async () => {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying contracts with the account:", deployer.address);
  
  // Deploy the contract
  const JPSGuard = await ethers.getContractFactory("JPSGuard");
  const jpsGuard = await JPSGuard.deploy(
    "https://example.com/metadata/", // URI
    10 // 10% transaction fee
  );
  
  await jpsGuard.waitForDeployment();
  console.log("JPSGuard deployed to:", await jpsGuard.getAddress());
  
  // Register additional services
  console.log("Registering additional services...");
  
  // Public service
  await jpsGuard.registerService(
    "https://example.com/public-service/",
    deployer.address,
    0, // price
    1000, // token count
    0, // ServiceStatus.Public
    true, // isLimitedToken
    true // active
  );
  
  // Paid service
  await jpsGuard.registerService(
    "https://example.com/paid-service/",
    deployer.address,
    ethers.parseEther("0.1"), // 0.1 ETH price
    500, // token count
    3, // ServiceStatus.Paid
    true, // isLimitedToken
    true // active
  );
  
  // Whitelisted service
  await jpsGuard.registerService(
    "https://example.com/whitelisted-service/",
    deployer.address,
    0, // price
    200, // token count
    4, // ServiceStatus.Whitelisted
    true, // isLimitedToken
    true // active
  );
  
  console.log("Services registered successfully!");
  
  // Final service count
  const serviceCount = await jpsGuard.serviceCount();
  console.log("Total services registered:", serviceCount.toString());
}

deployWithServices()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });