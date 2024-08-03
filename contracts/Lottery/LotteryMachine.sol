// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IRandomNumberGenerator.sol";
import "../libraries/Ownable.sol";
import "../libraries/ReentrancyGuard.sol";

// import "hardhat/console.sol";

contract LotteryMachine is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InvalidRngAddress();
    error InvalidStartLotteryStatus(Status status);
    error InvalidInjectFundsStatus(Status status);
    error InvalidBuyTicketStatus(Status status);
    error TicketOutOfRange();
    error UserHasAlreadyBought();
    error InvalidCloseLotteryStatus(Status status);
    error InvalidDrawNumberStatus(Status status);
    error InvalidClaimStatus(Status status);
    error NoRewardsToClaim();
    error InvalidRewardsToClaim();
    error BracketOutOfRange();
    error RewardsShouldBeHigher();
    error InvalidRewardsBreakdown();
    error FinalNumberHasBeenDrawn();
    error InvalidRewardBreakdown(uint256[6] rewardsBreakdown);
    error InvalidPriceInToken(uint256 price);
    error InvalidInjectRngStatus(Status status);

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
    uint256[6] private _tokenPerBracket;
    mapping(uint32 => uint256) private _numberTickets;
    mapping(uint32 => uint32) private _bracketCalculator;
    uint256 private _priceTicketInToken;
    uint32 public finalNumber;
    Status public status;
    IRandomNumberGenerator public rng;
    IERC20 public slt;

    event LotteryStarted(
        uint256[6] rewardsBreakdown,
        uint256 priceTicketInToken
    );
    event TicketBought(address indexed user, uint32 ticketNumber);
    event LotteryClosed();
    event NumberDrawn(uint32 finalNumber);
    event RewardClaimed(address indexed user, uint32 bracket, uint256 rewards);

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
        if (status != Status.Pending && status != Status.Open) {
            revert InvalidInjectRngStatus(status);
        }
        if (rngAddress == address(0)) {
            revert InvalidRngAddress();
        }
        rng = IRandomNumberGenerator(rngAddress);
        rng.acceptOwnership();
    }

    function injectFunds(uint256 amount) external nonReentrant {
        _amountCollected += amount;
        slt.safeTransferFrom(msg.sender, address(this), amount);
    }

    function startLottery(
        uint256[6] calldata rewardsBreakdown,
        uint256 priceTicketInToken
    ) external onlyOwner {
        if (status != Status.Pending) {
            revert InvalidStartLotteryStatus(status);
        }
        uint256 total = 0;
        for (uint32 i = 0; i < 6; i++) {
            total += rewardsBreakdown[i];
        }
        if (total != 10000) {
            revert InvalidRewardsBreakdown();
        }
        status = Status.Open;
        _rewardsBreakdown = rewardsBreakdown;
        _priceTicketInToken = priceTicketInToken;
        _tokenPerBracket = [
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0)
        ];
        emit LotteryStarted(rewardsBreakdown, priceTicketInToken);
    }

    function buyTicket(uint32 ticketNumber) external nonReentrant {
        if (status != Status.Open) {
            revert InvalidBuyTicketStatus(status);
        }
        if (ticketNumber < 1000000 || ticketNumber > 1999999) {
            revert TicketOutOfRange();
        }
        if (_userWithTicketNumber[msg.sender] != 0) {
            revert UserHasAlreadyBought();
        }
        _userWithTicketNumber[msg.sender] = ticketNumber;
        _amountCollected += _priceTicketInToken;
        slt.safeTransferFrom(msg.sender, address(this), _priceTicketInToken);
        _numberTickets[1 + (ticketNumber % 10)]++;
        _numberTickets[11 + (ticketNumber % 100)]++;
        _numberTickets[111 + (ticketNumber % 1000)]++;
        _numberTickets[1111 + (ticketNumber % 10000)]++;
        _numberTickets[11111 + (ticketNumber % 100000)]++;
        _numberTickets[111111 + (ticketNumber % 1000000)]++;
        emit TicketBought(msg.sender, ticketNumber);
    }

    function closeLottery() external onlyOwner {
        if (status != Status.Open) {
            revert InvalidCloseLotteryStatus(status);
        }
        status = Status.Close;
        rng.requestRandomNumber();
        emit LotteryClosed();
    }

    function drawFinalNumberAndMakeLotteryClaimable() external onlyOwner {
        if (status != Status.Close) {
            revert InvalidDrawNumberStatus(status);
        }
        if (address(rng) == address(0)) {
            revert InvalidRngAddress();
        }
        if (finalNumber != 0) {
            revert FinalNumberHasBeenDrawn();
        }
        uint256 randomResult = rng.viewResult();
        uint32 finalNumber_ = uint32(1000000 + (randomResult % 1000000));

        uint256 numberAddressesInPreviousBracket;
        for (uint32 i = 0; i < 6; i++) {
            uint32 j = 5 - i;
            uint32 transformedWinningNumber = _bracketCalculator[j] +
                (finalNumber_ % (uint32(10) ** (j + 1)));
            uint256 winnersInCurrentBracket = _numberTickets[
                transformedWinningNumber
            ] - numberAddressesInPreviousBracket;
            if (winnersInCurrentBracket != 0) {
                _tokenPerBracket[j] =
                    (_rewardsBreakdown[j] * _amountCollected) /
                    winnersInCurrentBracket /
                    10000;
                numberAddressesInPreviousBracket = _numberTickets[
                    transformedWinningNumber
                ];
            } else {
                _tokenPerBracket[j] = 0;
            }
        }
        finalNumber = finalNumber_;
        status = Status.Claimable;
        emit NumberDrawn(finalNumber);
    }

    function claimTicket(uint32 bracket) external nonReentrant {
        if (status != Status.Claimable) {
            revert InvalidClaimStatus(status);
        }
        if (bracket > 5) {
            revert BracketOutOfRange();
        }
        uint32 ticketNumber = _userWithTicketNumber[msg.sender];
        uint256 rewards = _calculateRewards(ticketNumber, bracket);
        if (rewards == 0) {
            revert NoRewardsToClaim();
        }
        if (rewards > _amountCollected) {
            revert InvalidRewardsToClaim();
        }
        if (bracket != 5) {
            uint256 higherRewards = _calculateRewards(
                ticketNumber,
                bracket + 1
            );
            if (higherRewards != 0) {
                revert RewardsShouldBeHigher();
            }
        }
        _amountCollected -= rewards;
        slt.safeTransfer(msg.sender, rewards);
        emit RewardClaimed(msg.sender, bracket, rewards);
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
            return _tokenPerBracket[bracket];
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
