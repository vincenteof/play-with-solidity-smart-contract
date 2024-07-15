// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRandomNumberGenerator {
    function getRandomNumber() external;
    function viewRandomResult() external view returns (uint256);
}
