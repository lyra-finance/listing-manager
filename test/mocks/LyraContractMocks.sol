//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "../../src/lyra-interfaces/IBaseExchangeAdapter.sol";
import "../../src/lyra-interfaces/ILiquidityPool.sol";
import "../../src/lyra-interfaces/IOptionGreekCache.sol";
import "../../src/lyra-interfaces/IOptionMarket.sol";
import "../../src/lyra-interfaces/IOptionMarketGovernanceWrapper.sol";
import "forge-std/Test.sol";

contract MockBaseExchangeAdapter is IBaseExchangeAdapter {
  function getSpotPriceForMarket(address, PriceType) external pure override returns (uint spot) {
    return spot;
  }
}

contract MockOptionMarket is IOptionMarket {
  function getBoardAndStrikeDetails(uint boardId)
    external
    pure
    override
    returns (
      OptionBoard memory board,
      Strike[] memory strikes,
      uint[] memory strikeToBaseReturnedRatios,
      uint priceAtExpiry,
      uint longScaleFactor
    )
  {
    return (board, strikes, strikeToBaseReturnedRatios, priceAtExpiry, longScaleFactor);
  }

  function getLiveBoards() external pure override returns (uint[] memory boardIds) {
    return (boardIds);
  }
}

contract MockOptionGreekCache is IOptionGreekCache {
  function getBoardGreeksView(uint boardId) external pure override returns (BoardGreeksView memory boardView) {
    return boardView;
  }

  function getOptionBoardCache(uint boardId) external pure override returns (OptionBoardCache memory boardCache) {
    return boardCache;
  }
}

contract MockLiquidityPool is ILiquidityPool {
  function CBTimestamp() external pure override returns (uint cbTimestamp) {
    return cbTimestamp;
  }
}

contract MockOptionMarketGovernanceWrapper is IOptionMarketGovernanceWrapper {
  function addStrikeToBoard(IOptionMarket market, uint boardId, uint strikePrice, uint skew) external {}

  function createOptionBoard(
    IOptionMarket market,
    uint expiry,
    uint baseIV,
    uint[] memory strikePrices,
    uint[] memory skews,
    bool frozen
  ) external returns (uint boardId) {
    return boardId;
  }
}
