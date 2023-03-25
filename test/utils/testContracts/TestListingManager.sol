//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "../../../src/ListingManager.sol";

contract TestListingManager is ListingManager {
  constructor(
    IBaseExchangeAdapter _exchangeAdapter,
    ILiquidityPool _liquidityPool,
    IOptionGreekCache _optionGreekCache,
    IOptionMarket _optionMarket,
    IOptionMarketGovernanceWrapper _governanceWrapper
  ) ListingManager(_exchangeAdapter, _liquidityPool, _optionGreekCache, _optionMarket, _governanceWrapper) {}

  function TEST_getNewBoardData(uint newExpiry)
    external
    view
    returns (uint baseIv, ListingManager.StrikeToAdd[] memory boards)
  {
    return _getNewBoardData(getAllBoardDetails(), newExpiry, getSpotPrice());
  }

  function TEST_fetchSurroundingBoards(
    BoardDetails[] memory boardDetails,
    uint expiry
  ) external view returns (VolGenerator.Board memory shortDated, VolGenerator.Board memory longDated) {
    return _fetchSurroundingBoards(boardDetails, expiry);
  }

  function TEST_quickSortStrikes(ListingManager.StrikeDetails[] memory arr)
    public
    pure
    returns (ListingManager.StrikeDetails[] memory result)
  {
    // sorting happens in place. ALWAYS pass in 0 and length - 1
    _quickSortStrikes(arr, 0, int(arr.length) - 1);
    // return a copy
    return arr;
  }

  function TEST_isCBActive() public view returns (bool) {
    return isCBActive();
  }
}
