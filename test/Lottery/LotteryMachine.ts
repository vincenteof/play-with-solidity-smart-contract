import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import hre from 'hardhat'

describe('LotteryMachine', () => {
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

    const LotteryMachine = await hre.ethers.getContractFactory('LotteryMachine')
    const SimpleLotteryToken = await hre.ethers.getContractFactory(
      'SimpleLotteryToken'
    )
    const slt = await SimpleLotteryToken.deploy(hre.ethers.parseEther('200000'))
    const lotteryMachine = await LotteryMachine.deploy(await slt.getAddress())

    await rng.transferOwnership(await lotteryMachine.getAddress())
    await lotteryMachine.injectRng(await rng.getAddress())

    await slt.approve(
      await lotteryMachine.getAddress(),
      hre.ethers.parseEther('150000')
    )
    await lotteryMachine.injectFunds(hre.ethers.parseEther('10000'))

    return { lotteryMachine, rng, vrfCoordinatorMock, slt, owner, otherAccount }
  }

  describe('Deployment', async () => {
    it('Should set correct initial state', async function () {
      const { lotteryMachine, slt, owner } = await loadFixture(deployFixture)
      expect(await slt.balanceOf(owner.address)).to.eq(
        hre.ethers.parseEther('200000') - hre.ethers.parseEther('10000')
      )
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('10000')
      )
      expect(await lotteryMachine.getAmountCollected()).to.eq(
        hre.ethers.parseEther('10000')
      )
    })
  })

  describe('Buy Ticket', async () => {
    it('should buy the ticket successfully', async () => {
      const { lotteryMachine, owner } = await loadFixture(deployFixture)
      await lotteryMachine.startLottery([500, 500, 500, 500, 3000, 5000], 5000n)
      await lotteryMachine.buyTicket(BigInt(1123456))
      expect(await lotteryMachine.getUserTicket(owner.address)).to.eq(
        BigInt(1123456)
      )
    })
  })

  describe('Close Lottery', async () => {
    it('should close the lottery successfully', async () => {
      const { lotteryMachine } = await loadFixture(deployFixture)
      await lotteryMachine.startLottery([500, 500, 500, 500, 3000, 5000], 5000n)
      await lotteryMachine.closeLottery()
      expect(await lotteryMachine.status()).to.eq(2n)
    })
  })

  describe('Draw the final number', async () => {
    it('should draw the final number successfully', async () => {
      const { lotteryMachine, rng, vrfCoordinatorMock } = await loadFixture(
        deployFixture
      )
      await lotteryMachine.startLottery([500, 500, 500, 500, 3000, 5000], 5000n)
      await lotteryMachine.closeLottery()
      await vrfCoordinatorMock.fulfillRandomWords(
        await rng.s_requestId(),
        await rng.getAddress()
      )
      await lotteryMachine.drawFinalNumberAndMakeLotteryClaimable()
      expect(await lotteryMachine.status()).to.eq(3n)
      const finalNumber = await lotteryMachine.finalNumber()
      expect(finalNumber).to.be.a('bigint')
      expect(finalNumber).within(1000000n, 1999999n)
    })
  })

  describe('Claim', async () => {
    it('should claim the tickets get some rewards', async function () {
      const { lotteryMachine, slt, rng, vrfCoordinatorMock } =
        await loadFixture(deployFixture)
      await lotteryMachine.startLottery([500, 500, 500, 500, 3000, 5000], 5000n)
      await lotteryMachine.buyTicket(1123456n)
      await lotteryMachine.closeLottery()
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        await rng.s_requestId(),
        await rng.getAddress(),
        [1123456n, 1654321n]
      )
      await lotteryMachine.drawFinalNumberAndMakeLotteryClaimable()
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('10000') + 5000n
      )
      await lotteryMachine.claimTicket(5)
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('5000') + 2500n
      )
    })
  })
})
