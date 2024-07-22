import { HardhatUserConfig } from 'hardhat/config'
import './toolbox'
import 'hardhat-abi-exporter'

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.24',
      },
      {
        version: '0.8.19',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200
          }
        }
      },
    ],
  },
  abiExporter: {
    path: './data/abi',
    clear: true,
    runOnCompile: true,
  },
}

export default config
