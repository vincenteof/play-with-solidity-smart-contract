// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRandomNumberGenerator.sol";
import "../libraries/Ownable.sol";

// import "hardhat/console.sol";

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
    uint256 private _priceTicketInCake;
    uint32 public finalNumber;
    Status public status;
    IRandomNumberGenerator public rng;
    IERC20 public slt;

    constructor(address sltAddress) Ownable(msg.sender) {
        slt = IERC20(sltAddress);
        status = Status.Pending;
        _bracketCalculator[0] = 1;
        _bracketCalculator[1] = 11;
        _bracketCalculator[2] = 111;
        _bracketCalculator[3] = 1111;
        _bracketCalculator[4] = 11111;
        _bracketCalculator[5] = 111111;
    }

    function injectRng(address rngAddress) external onlyOwner {
        rng = IRandomNumberGenerator(rngAddress);
        rng.acceptOwnership();
    }

    function injectFunds(uint256 amount) external {
        _amountCollected += amount;
        slt.transferFrom(msg.sender, address(this), amount);
    }

    function startLottery(
        uint256[6] calldata rewardsBreakdown,
        uint256 priceTicketInCake
    ) external onlyOwner {
        status = Status.Open;
        _rewardsBreakdown = rewardsBreakdown;
        _priceTicketInCake = priceTicketInCake;
    }

    function buyTicket(uint32 ticketNumber) external {
        _userWithTicketNumber[msg.sender] = ticketNumber;
        _amountCollected += _priceTicketInCake;
        slt.transferFrom(msg.sender, address(this), _priceTicketInCake);
    }

    function closeLottery() external onlyOwner {
        status = Status.Close;
        rng.requestRandomNumber();
    }

    function drawFinalNumberAndMakeLotteryClaimable() external onlyOwner {
        uint256 randomResult = rng.viewResult();
        uint32 finalNumber_ = uint32(1000000 + (randomResult % 1000000));
        finalNumber = finalNumber_;
        status = Status.Claimable;
    }

    function claimTicket(uint32 bracket) external {
        uint32 ticketNumber = _userWithTicketNumber[msg.sender];
        uint256 rewards = _calculateRewards(ticketNumber, bracket);
        if (rewards > 0 && rewards <= _amountCollected) {
            _amountCollected -= rewards;
            slt.transfer(msg.sender, rewards);
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

    function getUserTicket(address user) external view returns (uint32) {
        return _userWithTicketNumber[user];
    }

    function getAmountCollected() external view returns (uint256) {
        return _amountCollected;
    }
}
