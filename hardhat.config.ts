import { HardhatUserConfig } from 'hardhat/config'
import './toolbox'
import 'hardhat-abi-exporter'

const config: HardhatUserConfig = {
  solidity: '0.8.24',
  abiExporter: {
    path: './data/abi',
    clear: true,
    runOnCompile: true
  },
}

export default config
