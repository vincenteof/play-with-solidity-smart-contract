// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IRandomNumberGenerator.sol";
import "../libraries/Ownable.sol";
import "../libraries/ReentrancyGuard.sol";

contract LotteryMachine is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error InjectFundsWhenNotOpen();
    error NotTimeToStartLottery();
    error BuyicketWhenNotOpen();
    error TicketOutOfRange();
    error UserHasAlreadyBought();
    error NoTicketNumberToBuy();
    error CloseLotteryWhenNotOpen();
    error DrawNumberWhenNotClose();
    error ClaimWhenNotClaimable();
    error NoRewardsToClaim();
    error NotTheOwnerToClaim();
    error InvalidRewardsToClaim();
    error InvalidTicketIdToCliam();
    error UnmatchedTicketIdsAndBracketsToClaim();
    error NoTicketIdsToClaim();
    error BracketOutOfRange();
    error RewardsShouldBeHigher();
    error InvalidRewardsBreakdown();
    error FinalNumberHasBeenDrawn();

    enum Status {
        Pending,
        Open,
        Close,
        Claimable
    }

    struct Lottery {
        Status status;
        uint256 priceTicketInToken;
        // 500: 5% // 200: 2% // 50: 0.5%
        // adds up to 10000
        uint256[6] rewardsBreakdown;
        uint256[6] tokenPerBracket;
        uint256 amountCollected;
        uint32 finalNumber;
    }

    enum TicketStatus {
        NotCreated,
        Bought,
        Claimed
    }

    struct Ticket {
        TicketStatus status;
        uint32 number;
        address owner;
    }

    uint256 public currentLotteryId;
    uint256 public currentTicketId;

    mapping(uint256 => Lottery) private _lotteries;
    mapping(uint256 => Ticket) private _tickets;

    mapping(uint256 => mapping(uint32 => uint256))
        private _numberTicketsPerLotteryId;
    mapping(address => mapping(uint256 => uint256[]))
        private _userTicketIdsPerLotteryId;

    mapping(uint32 => uint32) private _bracketCalculator;
    IRandomNumberGenerator public rng;
    IERC20 public slt;

    event LotteryStarted(
        uint256 indexed lotteryId,
        uint256[6] rewardsBreakdown,
        uint256 priceTicketInToken
    );
    event TicketBought(
        uint256 indexed lotteryId,
        address indexed user,
        uint256 ticketNumbersLength
    );
    event LotteryClosed(uint256 indexed lotteryId);
    event NumberDrawn(uint256 indexed lotteryId, uint32 finalNumber);
    event RewardClaimed(
        uint256 indexed lotteryId,
        address indexed user,
        uint256 ticketNumbersLength,
        uint256 rewards
    );

    constructor(address sltAddress, address rngAddress) Ownable(msg.sender) {
        slt = IERC20(sltAddress);
        rng = IRandomNumberGenerator(rngAddress);
        _bracketCalculator[0] = 1;
        _bracketCalculator[1] = 11;
        _bracketCalculator[2] = 111;
        _bracketCalculator[3] = 1111;
        _bracketCalculator[4] = 11111;
        _bracketCalculator[5] = 111111;
    }

    function takeRngOwnership() external onlyOwner {
        rng.acceptOwnership();
    }

    function injectFunds(
        uint256 lotteryId,
        uint256 amount
    ) external nonReentrant {
        if (_lotteries[lotteryId].status != Status.Open) {
            revert InjectFundsWhenNotOpen();
        }
        _lotteries[lotteryId].amountCollected += amount;
        slt.safeTransferFrom(msg.sender, address(this), amount);
    }

    function startLottery(
        uint256[6] calldata rewardsBreakdown,
        uint256 priceTicketInToken
    ) external onlyOwner {
        if (
            currentLotteryId != 0 &&
            _lotteries[currentLotteryId].status != Status.Claimable
        ) {
            revert NotTimeToStartLottery();
        }
        uint256 total = 0;
        for (uint32 i = 0; i < 6; i++) {
            total += rewardsBreakdown[i];
        }
        if (total != 10000) {
            revert InvalidRewardsBreakdown();
        }
        currentLotteryId++;
        _lotteries[currentLotteryId].status = Status.Open;
        _lotteries[currentLotteryId].rewardsBreakdown = rewardsBreakdown;
        _lotteries[currentLotteryId].priceTicketInToken = priceTicketInToken;
        _lotteries[currentLotteryId].tokenPerBracket = [
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0),
            uint256(0)
        ];
        emit LotteryStarted(
            currentLotteryId,
            rewardsBreakdown,
            priceTicketInToken
        );
    }

    function buyTickets(
        uint256 lotteryId,
        uint32[] calldata ticketNumbers
    ) external nonReentrant {
        if (_lotteries[lotteryId].status != Status.Open) {
            revert BuyicketWhenNotOpen();
        }
        if (ticketNumbers.length == 0) {
            revert NoTicketNumberToBuy();
        }

        uint256 amountTokenToTransfer = _lotteries[lotteryId]
            .priceTicketInToken * ticketNumbers.length;
        slt.safeTransferFrom(msg.sender, address(this), amountTokenToTransfer);
        _lotteries[lotteryId].amountCollected += amountTokenToTransfer;

        for (uint256 i = 0; i < ticketNumbers.length; i++) {
            uint32 ticketNumber = ticketNumbers[i];
            if (ticketNumber < 1000000 || ticketNumber > 1999999) {
                revert TicketOutOfRange();
            }

            _numberTicketsPerLotteryId[lotteryId][1 + (ticketNumber % 10)]++;
            _numberTicketsPerLotteryId[lotteryId][11 + (ticketNumber % 100)]++;
            _numberTicketsPerLotteryId[lotteryId][
                111 + (ticketNumber % 1000)
            ]++;
            _numberTicketsPerLotteryId[lotteryId][
                1111 + (ticketNumber % 10000)
            ]++;
            _numberTicketsPerLotteryId[lotteryId][
                11111 + (ticketNumber % 100000)
            ]++;
            _numberTicketsPerLotteryId[lotteryId][
                111111 + (ticketNumber % 1000000)
            ]++;

            _userTicketIdsPerLotteryId[msg.sender][lotteryId].push(
                currentTicketId
            );
            _tickets[currentTicketId] = Ticket({
                number: ticketNumber,
                owner: msg.sender,
                status: TicketStatus.Bought
            });
            currentTicketId++;
        }

        emit TicketBought(lotteryId, msg.sender, ticketNumbers.length);
    }

    function closeLottery(uint256 lotteryId) external onlyOwner {
        if (_lotteries[lotteryId].status != Status.Open) {
            revert CloseLotteryWhenNotOpen();
        }
        _lotteries[lotteryId].status = Status.Close;
        rng.requestRandomNumber();
        emit LotteryClosed(lotteryId);
    }

    function drawFinalNumberAndMakeLotteryClaimable(
        uint256 lotteryId
    ) external onlyOwner {
        if (_lotteries[lotteryId].status != Status.Close) {
            revert DrawNumberWhenNotClose();
        }
        if (_lotteries[lotteryId].finalNumber != 0) {
            revert FinalNumberHasBeenDrawn();
        }
        uint256 randomResult = rng.viewResult();
        uint32 finalNumber_ = uint32(1000000 + (randomResult % 1000000));

        uint256 numberAddressesInPreviousBracket;
        for (uint32 i = 0; i < 6; i++) {
            uint32 j = 5 - i;
            uint32 transformedWinningNumber = _bracketCalculator[j] +
                (finalNumber_ % (uint32(10) ** (j + 1)));
            uint256 winnersInCurrentBracket = _numberTicketsPerLotteryId[
                lotteryId
            ][transformedWinningNumber] - numberAddressesInPreviousBracket;
            if (winnersInCurrentBracket != 0) {
                _lotteries[lotteryId].tokenPerBracket[j] =
                    (_lotteries[lotteryId].rewardsBreakdown[j] *
                        _lotteries[lotteryId].amountCollected) /
                    winnersInCurrentBracket /
                    10000;
                numberAddressesInPreviousBracket = _numberTicketsPerLotteryId[
                    lotteryId
                ][transformedWinningNumber];
            } else {
                _lotteries[lotteryId].tokenPerBracket[j] = 0;
            }
        }
        _lotteries[lotteryId].finalNumber = finalNumber_;
        _lotteries[lotteryId].status = Status.Claimable;
        emit NumberDrawn(lotteryId, finalNumber_);
    }

    function claimTicket(
        uint256 lotteryId,
        uint256[] calldata ticketIds,
        uint32[] calldata brackets
    ) external nonReentrant {
        if (_lotteries[lotteryId].status != Status.Claimable) {
            revert ClaimWhenNotClaimable();
        }
        if (ticketIds.length != brackets.length) {
            revert UnmatchedTicketIdsAndBracketsToClaim();
        }
        if (ticketIds.length == 0) {
            revert NoTicketIdsToClaim();
        }

        uint256 rewardsInTokenToTransfer = 0;
        for (uint256 i = 0; i < ticketIds.length; i++) {
            uint32 bracket = brackets[i];
            if (bracket > 5) {
                revert BracketOutOfRange();
            }
            uint256 ticketId = ticketIds[i];
            if (_tickets[ticketId].status != TicketStatus.Bought) {
                revert InvalidTicketIdToCliam();
            }
            if (msg.sender != _tickets[ticketId].owner) {
                revert NotTheOwnerToClaim();
            }
            _tickets[ticketId].owner = address(0);
            _tickets[ticketId].status = TicketStatus.Claimed;
            uint256 reward = _calculateRewards(lotteryId, ticketId, bracket);

            if (reward == 0) {
                revert NoRewardsToClaim();
            }
            if (reward > _lotteries[lotteryId].amountCollected) {
                revert InvalidRewardsToClaim();
            }
            if (bracket != 5) {
                uint256 higherRewards = _calculateRewards(
                    lotteryId,
                    ticketId,
                    bracket + 1
                );
                if (higherRewards != 0) {
                    revert RewardsShouldBeHigher();
                }
            }
            rewardsInTokenToTransfer += reward;
        }

        slt.safeTransfer(msg.sender, rewardsInTokenToTransfer);
        emit RewardClaimed(
            lotteryId,
            msg.sender,
            ticketIds.length,
            rewardsInTokenToTransfer
        );
    }

    function _calculateRewards(
        uint256 lotteryId,
        uint256 ticketId,
        uint32 bracket
    ) internal view returns (uint256) {
        uint32 ticketNumber = _tickets[ticketId].number;
        uint32 transformedTicketNumber = _bracketCalculator[bracket] +
            (ticketNumber % (uint32(10) ** (bracket + 1)));
        uint32 finalNumber = _lotteries[lotteryId].finalNumber;
        uint32 transformedFinalNumber = _bracketCalculator[bracket] +
            (finalNumber % (uint32(10) ** (bracket + 1)));
        if (transformedFinalNumber == transformedTicketNumber) {
            return _lotteries[lotteryId].tokenPerBracket[bracket];
        } else {
            return 0;
        }
    }

    function getUserTicketIds(
        uint256 lotteryId,
        address user
    ) external view returns (uint256[] memory) {
        return _userTicketIdsPerLotteryId[user][lotteryId];
    }

    function getTicket(uint256 ticketId) external view returns (Ticket memory) {
        return _tickets[ticketId];
    }

    function getLottery(
        uint256 lotteryId
    ) external view returns (Lottery memory) {
        return _lotteries[lotteryId];
    }
}
