// require("@nomicfoundation/hardhat-toolbox");

// /** @type import('hardhat/config').HardhatUserConfig */
// module.exports = {
//   solidity: "0.8.24",
// };

// export default config;

require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");

// const config: HardhatUserConfig = {
module.exports = {
  solidity: "0.8.24",
  contractSizer: {
    runOnCompile: true,
    strict: true,
  },
};
