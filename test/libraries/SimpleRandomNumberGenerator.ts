import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import hre from 'hardhat'

describe('SimpleRandomNumberGenerator', () => {
  async function deployFixture() {
    const [owner, otherAccount] = await hre.ethers.getSigners()

    const SimpleRandomNumberGenerator = await hre.ethers.getContractFactory(
      'SimpleRandomNumberGenerator'
    )
    const VRFCoordinatorV2_5Mock = await hre.ethers.getContractFactory(
      'VRFCoordinatorV2_5Mock'
    )
    const vrfCoordinatorMock = await VRFCoordinatorV2_5Mock.deploy(
      BigInt('100000000000000000'),
      BigInt('1000000000'),
      BigInt('4055010000000000')
    )
    const tx = await vrfCoordinatorMock.createSubscription()
    const receipt = await tx.wait()
    if (!receipt?.blockNumber) {
      throw new Error('Error retrieving mocked coordinator subscription id')
    }

    const event = (
      await vrfCoordinatorMock.queryFilter(
        vrfCoordinatorMock.filters.SubscriptionCreated,
        receipt.blockNumber,
        receipt.blockNumber
      )
    )[0]

    const subId = event?.args?.subId
    if (!subId) {
      throw new Error('Error retrieving mocked coordinator subscription id')
    }

    await vrfCoordinatorMock.fundSubscription(
      subId,
      BigInt('100000000000000000000')
    )

    const rng = await SimpleRandomNumberGenerator.deploy(
      BigInt(subId),
      await vrfCoordinatorMock.getAddress(),
      '0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae'
    )

    await vrfCoordinatorMock.addConsumer(subId, await rng.getAddress())

    return { rng, vrfCoordinatorMock, owner, otherAccount }
  }

  describe('Generates Random Number', async () => {
    it('Should return a bigint', async function () {
      const { rng, vrfCoordinatorMock } = await loadFixture(deployFixture)
      await rng.requestRandomNumber()
      // call the method on coordinator manually
      await vrfCoordinatorMock.fulfillRandomWords(
        await rng.s_requestId(),
        await rng.getAddress()
      )
      const number = await rng.viewResult()
      expect(number).to.be.a('bigint')
    })
  })
})
