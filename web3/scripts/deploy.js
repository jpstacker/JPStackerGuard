const { ethers } = require("hardhat");

const deploy  = async () => {
  // Get the contract factory
  const JPSGuard = await ethers.getContractFactory("JPSGuard");
    
  console.log("Deploying JPSGuard contract...");
  
  // Deploy the contract
  const jpsGuard = await JPSGuard.deploy(
    "https://example.com/metadata/", // URI
    10 // 10% transaction fee
  );
  
  // Wait for deployment to complete
  await jpsGuard.waitForDeployment();
  
  console.log("JPSGuard deployed to:", await jpsGuard.getAddress());
  
//   // Verify the deployment
//   const owner = await jpsGuard.owner();
//   console.log("Contract owner:", owner);
  
//   const serviceCount = await jpsGuard.serviceCount();
//   console.log("Initial service count:", serviceCount.toString());
  
//   // You can add more verification or initial setup here if needed
}

deploy()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

