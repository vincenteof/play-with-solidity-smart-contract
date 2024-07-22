// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/shared/interfaces/IOwnable.sol";

interface IRandomNumberGenerator is IOwnable {
    function requestRandomNumber() external;

    function viewResult() external view returns (uint256);
}
