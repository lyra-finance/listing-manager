//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "./IOptionMarket.sol";

interface IOptionMarketGovernanceWrapper {
  function createOptionBoard(uint expiry, uint baseIV, uint[] memory strikePrices, uint[] memory skews, bool frozen)
    external
    returns (uint boardId);

  function addStrikeToBoard(uint boardId, uint strikePrice, uint skew) external;
}
