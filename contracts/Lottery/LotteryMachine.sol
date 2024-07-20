// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRandomNumberGenerator.sol";
import "../libraries/Ownable.sol";

contract LotteryMachine is Ownable {
    enum Status {
        Pending,
        Open,
        Close,
        Claimable
    }

    mapping(address => uint32) private _userWithTicketNumber;
    // 500: 5% // 200: 2% // 50: 0.5%
    // adds up to 10000
    uint256[6] private _rewardsBreakdown;
    uint256 private _amountCollected;
    mapping(uint32 => uint32) private _bracketCalculator;
    uint32 public finalNumber;
    Status public status;
    IRandomNumberGenerator public rng;
    IERC20 public simpleLotteryToken;

    constructor(address sltAddress, address rngAddress) Ownable(msg.sender) {
        rng = IRandomNumberGenerator(rngAddress);
        simpleLotteryToken = IERC20(sltAddress);
        status = Status.Pending;
        _bracketCalculator[0] = 1;
        _bracketCalculator[1] = 11;
        _bracketCalculator[2] = 111;
        _bracketCalculator[3] = 1111;
        _bracketCalculator[4] = 11111;
        _bracketCalculator[5] = 111111;
    }

    function injectFunds(uint256 amount) external {
        // todo: add transfer
        _amountCollected += amount;
    }

    function startLottery(
        uint256[6] calldata rewardsBreakdown
    ) external onlyOwner {
        status = Status.Open;
        _rewardsBreakdown = rewardsBreakdown;
    }

    function buyTicket(uint32 ticketNumber) external {
        _userWithTicketNumber[msg.sender] = ticketNumber;
    }

    function closeLottery() external onlyOwner {
        status = Status.Close;
        rng.getRandomNumber();
    }

    function drawTheFinalNumber() external onlyOwner {
        uint256 randomResult = rng.viewRandomResult();
        uint32 finalNumber_ = uint32(1000000 + (randomResult % 1000000));
        finalNumber = finalNumber_;
    }

    function claimTicket(uint32 bracket) external {
        uint32 ticketNumber = _userWithTicketNumber[msg.sender];
        uint256 rewards = _calculateRewards(ticketNumber, bracket);
        if (rewards > 0) {
            simpleLotteryToken.transfer(msg.sender, rewards);
        }
    }

    function _calculateRewards(
        uint32 ticketNumber,
        uint32 bracket
    ) internal view returns (uint256) {
        uint32 transformedTicketNumber = _bracketCalculator[bracket] +
            (ticketNumber % (uint32(10) ** (bracket + 1)));
        uint32 transformedFinalNumber = _bracketCalculator[bracket] +
            (finalNumber % (uint32(10) ** (bracket + 1)));
        if (transformedFinalNumber == transformedTicketNumber) {
            return (_amountCollected * _rewardsBreakdown[bracket]) / 10000;
        } else {
            return 0;
        }
    }
}
