//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "./IOptionMarket.sol";

interface IOptionMarketGovernanceWrapper {
  function createOptionBoard(
    IOptionMarket _optionMarket,
    uint expiry,
    uint baseIV,
    uint[] memory strikePrices,
    uint[] memory skews,
    bool frozen
  ) external returns (uint boardId);

  function addStrikeToBoard(IOptionMarket _optionMarket, uint boardId, uint strikePrice, uint skew) external;
}
