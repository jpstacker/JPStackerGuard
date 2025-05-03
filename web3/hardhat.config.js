require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  // solidity: "0.8.28",
  solidity: {
    version: "0.8.28",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  // contractSizer: {
  //   runOnCompile: true,
  //   strict: true,
  // },
  networks: {
    hardhat: {
      chainId: 1337,
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    mainnet: {
      url: process.env.MAINNET_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};


// PRIVATE_KEY=your_private_key_here
// SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your-infura-key
// MAINNET_RPC_URL=https://mainnet.infura.io/v3/your-infura-key
// ETHERSCAN_API_KEY=your_etherscan_api_key

// npx hardhat run scripts/deploy.js --network sepolia
