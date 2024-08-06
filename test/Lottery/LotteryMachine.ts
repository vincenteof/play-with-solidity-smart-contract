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
    const lotteryMachine = await LotteryMachine.deploy(
      await slt.getAddress(),
      await rng.getAddress()
    )
    await rng.transferOwnership(await lotteryMachine.getAddress())
    await lotteryMachine.takeRngOwnership()

    await slt.approve(
      await lotteryMachine.getAddress(),
      hre.ethers.parseEther('15000')
    )

    await slt
      .connect(otherAccount)
      .approve(await lotteryMachine.getAddress(), hre.ethers.parseEther('1000'))
    await slt.transfer(otherAccount.address, hre.ethers.parseEther('10000'))

    async function startLotteryAndInjectFunds(
      rewardsBreakdown = [500, 500, 500, 500, 3000, 5000],
      priceTicketInToken = 5000n,
      funds = hre.ethers.parseEther('10000')
    ) {
      await lotteryMachine.startLottery(rewardsBreakdown, priceTicketInToken)
      const lotteryId = await lotteryMachine.currentLotteryId()
      await lotteryMachine.injectFunds(lotteryId, funds)

      return {
        lotteryId,
      }
    }

    return {
      lotteryMachine,
      rng,
      vrfCoordinatorMock,
      slt,
      owner,
      otherAccount,
      startLotteryAndInjectFunds,
    }
  }

  describe('Inject Funds', async () => {
    it('should set correct initial state after injecting funds', async function () {
      const {
        lotteryMachine,
        slt,
        owner,
        otherAccount,
        startLotteryAndInjectFunds,
      } = await loadFixture(deployFixture)
      const { lotteryId } = await startLotteryAndInjectFunds()
      expect(await slt.balanceOf(owner.address)).to.eq(
        hre.ethers.parseEther('200000') -
          hre.ethers.parseEther('10000') -
          hre.ethers.parseEther('10000')
      )
      expect(await slt.balanceOf(otherAccount.address)).to.eq(
        hre.ethers.parseEther('10000')
      )
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('10000')
      )
      const lottery = lotteryMachine.getLottery(lotteryId)
      expect((await lottery).amountCollected).to.eq(
        hre.ethers.parseEther('10000')
      )
    })
    it('should set correct initial state for another lottery', async function () {
      const {
        lotteryMachine,
        vrfCoordinatorMock,
        rng,
        slt,
        owner,
        otherAccount,
        startLotteryAndInjectFunds,
      } = await loadFixture(deployFixture)
      const { lotteryId: firstLotteryId } = await startLotteryAndInjectFunds()
      await lotteryMachine.closeLottery(firstLotteryId)
      await vrfCoordinatorMock.fulfillRandomWords(
        await rng.s_requestId(),
        await rng.getAddress()
      )
      await lotteryMachine.drawFinalNumberAndMakeLotteryClaimable(
        firstLotteryId
      )
      expect(await slt.balanceOf(owner.address)).to.eq(
        hre.ethers.parseEther('200000') -
          hre.ethers.parseEther('10000') -
          hre.ethers.parseEther('10000')
      )
      expect(await slt.balanceOf(otherAccount.address)).to.eq(
        hre.ethers.parseEther('10000')
      )
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('10000')
      )
      const firstLottery = await lotteryMachine.getLottery(firstLotteryId)
      expect(firstLottery.amountCollected).to.eq(hre.ethers.parseEther('10000'))
      const { lotteryId: secondLotteryId } = await startLotteryAndInjectFunds(
        [500, 500, 500, 500, 3000, 5000],
        5000n,
        hre.ethers.parseEther('2000')
      )
      expect(await slt.balanceOf(owner.address)).to.eq(
        hre.ethers.parseEther('200000') -
          hre.ethers.parseEther('10000') -
          hre.ethers.parseEther('10000') -
          hre.ethers.parseEther('2000')
      )
      expect(await slt.balanceOf(otherAccount.address)).to.eq(
        hre.ethers.parseEther('10000')
      )
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('10000') + hre.ethers.parseEther('2000')
      )
      const secondLottery = await lotteryMachine.getLottery(secondLotteryId)
      expect(secondLottery.amountCollected).to.eq(hre.ethers.parseEther('2000'))
    })
  })

  describe('Buy Ticket', async () => {
    it('should buy the ticket successfully', async () => {
      const { lotteryMachine, owner, startLotteryAndInjectFunds } =
        await loadFixture(deployFixture)
      const { lotteryId } = await startLotteryAndInjectFunds()
      await lotteryMachine.buyTicket(lotteryId, BigInt(1123456))
      expect(
        await lotteryMachine.getUserTicket(lotteryId, owner.address)
      ).to.eq(BigInt(1123456))
    })
  })

  describe('Close Lottery', async () => {
    it('should close the lottery successfully', async () => {
      const { lotteryMachine, startLotteryAndInjectFunds } = await loadFixture(
        deployFixture
      )
      const { lotteryId } = await startLotteryAndInjectFunds()
      await lotteryMachine.closeLottery(lotteryId)
      const lottery = await lotteryMachine.getLottery(lotteryId)
      expect(lottery.status).to.eq(2n)
    })
  })

  describe('Draw the final number', async () => {
    it('should draw the final number successfully', async () => {
      const {
        lotteryMachine,
        rng,
        vrfCoordinatorMock,
        startLotteryAndInjectFunds,
      } = await loadFixture(deployFixture)
      const { lotteryId } = await startLotteryAndInjectFunds()
      await lotteryMachine.closeLottery(lotteryId)
      await vrfCoordinatorMock.fulfillRandomWords(
        await rng.s_requestId(),
        await rng.getAddress()
      )
      await lotteryMachine.drawFinalNumberAndMakeLotteryClaimable(lotteryId)
      const lottery = await lotteryMachine.getLottery(lotteryId)
      expect(lottery.status).to.eq(3n)
      const finalNumber = lottery.finalNumber
      expect(finalNumber).to.be.a('bigint')
      expect(finalNumber).within(1000000n, 1999999n)
    })
  })

  describe('Claim', async () => {
    it('should claim the tickets get some rewards', async function () {
      const {
        lotteryMachine,
        slt,
        rng,
        vrfCoordinatorMock,
        startLotteryAndInjectFunds,
      } = await loadFixture(deployFixture)
      const { lotteryId } = await startLotteryAndInjectFunds()
      await lotteryMachine.buyTicket(lotteryId, 1123456n)
      await lotteryMachine.closeLottery(lotteryId)
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        await rng.s_requestId(),
        await rng.getAddress(),
        [1123456n, 1654321n]
      )
      await lotteryMachine.drawFinalNumberAndMakeLotteryClaimable(lotteryId)
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('10000') + 5000n
      )
      await lotteryMachine.claimTicket(lotteryId, 5)
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('5000') + 2500n
      )
    })

    it('should divide the reward to different users', async function () {
      const {
        lotteryMachine,
        slt,
        rng,
        vrfCoordinatorMock,
        owner,
        otherAccount,
        startLotteryAndInjectFunds,
      } = await loadFixture(deployFixture)
      const { lotteryId } = await startLotteryAndInjectFunds(
        [500, 500, 500, 500, 2000, 6000],
        5000n
      )
      await lotteryMachine.buyTicket(lotteryId, 1023456n)
      await lotteryMachine.connect(otherAccount).buyTicket(lotteryId, 1323456n)
      await lotteryMachine.closeLottery(lotteryId)
      await vrfCoordinatorMock.fulfillRandomWordsWithOverride(
        await rng.s_requestId(),
        await rng.getAddress(),
        [1123456n, 1654321n]
      )
      await lotteryMachine.drawFinalNumberAndMakeLotteryClaimable(lotteryId)
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('10000') + 5000n + 5000n
      )
      await lotteryMachine.claimTicket(lotteryId, 4)
      await lotteryMachine.connect(otherAccount).claimTicket(lotteryId, 4)
      expect(await slt.balanceOf(await lotteryMachine.getAddress())).to.eq(
        hre.ethers.parseEther('8000') + 4000n + 4000n
      )
      expect(await slt.balanceOf(owner.address)).to.eq(
        hre.ethers.parseEther('180000') -
          5000n +
          hre.ethers.parseEther('1000') +
          1000n
      )
      expect(await slt.balanceOf(otherAccount.address)).to.eq(
        hre.ethers.parseEther('10000') -
          5000n +
          hre.ethers.parseEther('1000') +
          1000n
      )
    })
  })

  // todo: test another
})
