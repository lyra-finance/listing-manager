//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "../../../src/ListingManager.sol";

contract TestListingManager is ListingManager {
  constructor(
    IBaseExchangeAdapter _exchangeAdapter,
    ILiquidityPool _liquidityPool,
    IOptionGreekCache _optionGreekCache,
    IOptionMarket _optionMarket
  ) ListingManager(_exchangeAdapter, _liquidityPool, _optionGreekCache, _optionMarket) {}
  //
  //  function TEST_takeMarketOwnership() external {
  //    optionMarket.acceptOwnership();
  //  }

  function TEST_getNewBoardData(uint newExpiry)
    external
    returns (uint baseIv, ListingManager.StrikeToAdd[] memory strikesToAdd)
  {
    return _getNewBoardData(newExpiry);
  }
}
