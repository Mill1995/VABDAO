const { utils } = require("ethers");

require('dotenv').config();
require("@nomiclabs/hardhat-waffle");
require("hardhat-deploy");
require("hardhat-deploy-ethers");

if (process.env.NETWORK == "polygonAmoy") {
  require("@nomicfoundation/hardhat-verify");    
} else {
  require("@nomiclabs/hardhat-etherscan");  
}

require("hardhat-contract-sizer");
require("hardhat-gas-reporter")
require("solidity-coverage")
require("@nomicfoundation/hardhat-network-helpers")


task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {  
  const accounts = await hre.ethers.getSigners();

  for(const account of accounts) {
    console.log(account.address);
  }
});

console.log("Hardhat config Network: ", process.env.NETWORK);

const alchemy_key = process.env.ALCHEMY_KEY;
const etherScan_api_key = process.env.ETHER_SCAN_API_KEY;
const bscScan_api_key = process.env.BSC_SCAN_API_KEY;
const polyScan_api_key = process.env.POLYGON_SCAN_API_KEY;
const avaxScan_api_key = process.env.AVAX_SCAN_API_KEY;
const amoyScan_api_key = process.env.AMOY_SCAN_API_KEY;
const sepoliaScan_api_key = process.env.SEPOLIA_SCAN_API_KEY;
const baseScan_api_key = process.env.BASE_SCAN_API_KEY;

const mnemonic = process.env.MNEMONIC;
const privateKey = process.env.DEPLOY_PRIVATE_KEY;
const coinmarketcap_api_key = process.env.COINMARKETCAP_API_KEY;

let local_rpc_url = ``;
if (process.env.NETWORK == "polygonAmoy") {
  local_rpc_url = `https://rpc-amoy.polygon.technology/`;
}

if (process.env.NETWORK == "baseSepolia") {
  local_rpc_url = `https://sepolia.base.org/`;
}

const chainIds = {
  ganache: 1337,
  goerli: 5,
  hardhat: 31337,
  kovan: 42,
  mainnet: 1,
  rinkeby: 4,
  ropsten: 3,
  bscTest: 97,   // BSC testnet
  bscMain: 56,   // BSC mainnet
  mumbai: 80001, // Polygon testnet
  amoy: 80002, // Amoy testnet
  baseSepolia: 84532, // Sepolia testnet
  base: 8453,			// Base mainnet
  matic: 137,    // Polygon mainnet
  fuji: 43113,   // Avalance testnet
  avax: 43114,   // Avalance mainnet
};
if (!mnemonic || !alchemy_key) {
  throw new Error("Please set your data in a .env file");
}

module.exports = {
  defaultNetwork: 'hardhat',
  gasReporter: {
    coinmarketcap: coinmarketcap_api_key,
    currency: "USD",
    enabled: false
  },
  namedAccounts: {
    deployer: {
      default: 0,
    },
    dev: {
      default: 1,
    },
  },
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      chainId: chainIds.ganache,
      saveDeployments: true,
      forking: {
        // blockNumber: 11328709,
        url: local_rpc_url
      },
      accounts: {
        mnemonic,
      },  
      // accounts: [
      //   {
      //     privateKey: privateKey,
      //     balance: "1000000000000000000000000000"
      //   }
      // ],

      gasPrice: 22500000000,
      gasMultiplier: 2,
      // throwOnTransactionFailures: true,
      // blockGasLimit: 1245000000 
      blockGasLimit: 3245000000 
    },
    // Ethereum mainnet
    mainnet: { 
      url: `https://eth-mainnet.alchemyapi.io/v2/${alchemy_key}`,
      accounts: [
        privateKey
      ],
      chainId: chainIds.mainnet,
      live: false,
      saveDeployments: true
    },
    // Ethereum testnet(Goerli)
    goerli: { 
      url: `https://eth-goerli.alchemyapi.io/v2/${alchemy_key}`,
      accounts: [
        privateKey
      ],
      chainId: chainIds.goerli,
      live: false,
      saveDeployments: true,
      tags: ["staging"],
      gasPrice: 5000000000,
      gasMultiplier: 2,
    },
    // BSC testnet
    bscTest: { 
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      chainId: chainIds.bscTest,
      accounts: [
        privateKey
      ],
      live: true,
      saveDeployments: true,
      gasMultiplier: 2,
    },
    // BSC mainnet
    bscMain: { 
      url: "https://bsc-dataseed.binance.org/",
      chainId: chainIds.bscMain,
      accounts: [
        privateKey
      ],
      live: true,
      saveDeployments: true
    },
    // Polygon testnet
    mumbai: { 
      // url: "https://rpc-mumbai.maticvigil.com",
      url: "https://polygon-mumbai.g.alchemy.com/v2/MS1xXvCUQzKUdIBnUrKZpdx26AHMixO4",
      chainId: chainIds.mumbai,
      accounts: [
        privateKey
      ],
      live: false,
      saveDeployments: true,
      gasPrice: 22500000000,
      gasMultiplier: 2,
    },
    // Amoy testnet
    polygonAmoy: {       
      url: "https://rpc-amoy.polygon.technology/",
      chainId: chainIds.amoy,
      accounts: [
        privateKey
      ],
      live: false,
      saveDeployments: true,
      gasPrice: 22500000000,
      gasMultiplier: 2
    },
    // Base Sepolia testnet
    baseSepolia: {       
      url: "https://sepolia.base.org/",
      chainId: chainIds.baseSepolia,
      accounts: [
        privateKey
      ],
      live: false,
      saveDeployments: true,
      gasPrice: 22500000000,
      gasMultiplier: 2
    },
    // Base mainnet
		base: {
			url: `https://base-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
			chainId: chainIds.base,
			accounts: [
				privateKey,
			],
			live: true,
			saveDeployments: true
		},
    // Polygon mainnet
    matic: { 
      url: "https://polygon-rpc.com",
      chainId: chainIds.matic,
      accounts: [
        privateKey
      ],
      live: true,
      saveDeployments: true
    },
    // Avalance testnet(Fuji: C-Chain)
    fuji: { 
      url: "https://api.avax-test.network/ext/C/rpc",
      gasPrice: 225000000000,
      chainId: chainIds.fuji,
      accounts: [
        privateKey
      ],
    },
    // Avalance mainnet
    avax: { 
      url: "https://api.avax.network/ext/bc/C/rpc",
      gasPrice: 225000000000,
      chainId: chainIds.avax,
      accounts: {
        mnemonic,
      },
      live: true,
      saveDeployments: true
    },
  },
  etherscan: {
    // apiKey: etherScan_api_key,
    // apiKey: bscScan_api_key,    
    // apiKey: polyScan_api_key,
    // apiKey: avaxScan_api_key,
    // apiKey: baseScan_api_key,
    apiKey: baseScan_api_key,
    // apiKey: {
    //   polygonAmoy: amoyScan_api_key,
    //   baseSepolia: sepoliaScan_api_key + '1'
    // },
    customChains: [
      {
        network: "polygonAmoy",
        chainId: chainIds.amoy,
        urls: {
          apiURL: "https://www.oklink.com/api/v5/explorer/contract/verify-source-code-plugin/AMOY_TESTNET",
          // apiURL: "https://www.oklink.com/api/explorer/v1/polygonamoy/contract/verify/async",
          browserURL: "https://www.oklink.com/amoy",
        },
      },
      {
        network: "baseSepolia",
        chainId: chainIds.baseSepolia,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          // apiURL: "https://www.oklink.com/api/explorer/v1/polygonamoy/contract/verify/async",
          browserURL: "https://base-sepolia.blockscout.com",
        },
      },
    ], 
  },
  sourcify: {
    enabled: false,
    // // Optional: specify a different Sourcify server
    // apiUrl: "https://sourcify.dev/server",
    // // Optional: specify a different Sourcify repository
    // browserUrl: "https://repo.sourcify.dev",
    apiUrl: "https://server-verify.hashscan.io",
    browserUrl: "https://repository-verify.hashscan.io",

  },
  paths: {
    deploy: "deploy",
    deployments: "deployments",
    sources: "contracts",
    tests: "test"
  },
  mocha: {
    timeout: 200e3
  },
  solidity: {
    compilers: [
      {
        version: '0.8.4',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },        
      },
    ],
  }
};
