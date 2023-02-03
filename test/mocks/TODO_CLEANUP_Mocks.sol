import "../../src/TODO_CLEANUP_Interfaces.sol";

contract MockBaseExchangeAdapter is IBaseExchangeAdapter {
  function getSpotPriceForMarket(address, PriceType) external view override returns (uint spot) {
    return spot;
  }
}

contract MockLyraRegistry is ILyraRegistry {
  function getMarketAddresses(address optionMarket)
    external
    view
    override
    returns (OptionMarketAddresses memory addresses)
  {
    return addresses;
  }

  function getGlobalAddress(bytes32 contractName) external view override returns (address globalContract) {
    return globalContract;
  }
}

contract MockOptionMarket is IOptionMarket {
  function getBoardAndStrikeDetails(uint boardId)
    external
    view
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
}

contract MockOptionGreekCache is IOptionGreekCache {
  function getBoardGreeksView(uint boardId) external view override returns (BoardGreeksView memory boardView) {
    return boardView;
  }

  function getOptionBoardCache(uint boardId) external view override returns (OptionBoardCache memory boardCache) {
    return boardCache;
  }
}
