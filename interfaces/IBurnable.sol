// SPDX-License-Identifier: MIT
pragma solidity 0.7.5;

interface IBurnable {
  function burnFrom(address account, uint256 amount) external;
}