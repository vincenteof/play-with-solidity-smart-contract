// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
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
    uint32 public finalNumber;
    Status public status;
    IRandomNumberGenerator public rng;

    constructor(address rngAddress) {
        rng = IRandomNumberGenerator(rngAddress);
        status = Status.Pending;
    }

    function startLottery() external onlyOwner {
        status = Status.Open;
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

    function claimTicket() external {
        uint32 ticketNumber = _userWithTicketNumber[msg.sender];
        uint256 rewards = _calculateRewards(ticketNumber);
        // todo: transfer the rewards to the user
    }

    function _calculateRewards(
        uint32 ticketNumber
    ) internal view returns (uint256) {
        // todo: calculate rewards for some ticket number
        return 0;
    }
}
