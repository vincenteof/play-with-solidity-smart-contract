import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import hre from 'hardhat'
import { MerkleTree } from 'merkletreejs'

describe('MerkleProofVerifier', () => {
  async function deployFixture() {
    const MerkleProof = await hre.ethers.getContractFactory('MerkleProof')
    const merkleProof = await MerkleProof.deploy()
    const MerkleProofVerifier = await hre.ethers.getContractFactory(
      'MerkleProofVerifier',
      // resolve the link problem
      {
        libraries: {
          MerkleProof: merkleProof,
        },
      }
    )
    const merkleProofVerifier = await MerkleProofVerifier.deploy()
    return {
      merkleProofVerifier,
    }
  }

  it('should verify a merkle proof in a unsorted merkle tree', async () => {
    const { merkleProofVerifier } = await loadFixture(deployFixture)
    const leaves = ['a', 'b', 'c'].map((x) =>
      hre.ethers.keccak256(hre.ethers.toUtf8Bytes(x))
    )
    const tree = new MerkleTree(leaves, hre.ethers.keccak256, { sort: false })
    const leaf0 = leaves[0]
    const leaf1 = leaves[1]
    const proof0 = tree.getHexProof(leaf0)
    const proof1 = tree.getHexProof(leaf1)
    const root = tree.getHexRoot()
    expect(await merkleProofVerifier.verify(proof0, root, leaf0, 0)).to.be.true
    expect(await merkleProofVerifier.verify(proof1, root, leaf1, 1)).to.be.true
    expect(await merkleProofVerifier.verify(proof0, root, leaf1, 0)).to.be.false
    expect(await merkleProofVerifier.verify(proof1, root, leaf0, 1)).to.be.false
  })

  it('should verify a merkle proof in a sorted merkle tree', async () => {
    const { merkleProofVerifier } = await loadFixture(deployFixture)
    const leaves = ['a', 'b', 'c'].map((x) =>
      hre.ethers.keccak256(hre.ethers.toUtf8Bytes(x))
    )
    const tree = new MerkleTree(leaves, hre.ethers.keccak256, { sort: true })
    const leaf0 = leaves[0]
    const leaf1 = leaves[1]
    const proof0 = tree.getHexProof(leaf0)
    const proof1 = tree.getHexProof(leaf1)
    const root = tree.getHexRoot()
    expect(await merkleProofVerifier.verifyBySorting(proof0, root, leaf0)).to.be
      .true
    expect(await merkleProofVerifier.verifyBySorting(proof0, root, leaf1)).to.be
      .false
    expect(await merkleProofVerifier.verifyBySorting(proof1, root, leaf1)).to.be
      .true
    expect(await merkleProofVerifier.verifyBySorting(proof1, root, leaf0)).to.be
      .false
  })
})
