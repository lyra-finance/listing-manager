// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/ListingManager.sol";
import "./mocks/TODO_CLEANUP_Mocks.sol";

contract ListingManagerTestBase is Test {
  IOptionGreekCache greekCache;
  IOptionMarket optionMarket;
  ILyraRegistry lyraRegistry;
  IBaseExchangeAdapter exchangeAdapter;
  ListingManager listingManager;

  constructor() {}

  function setUp() public {
    greekCache = new MockOptionGreekCache();
    optionMarket = new MockOptionMarket();
    lyraRegistry = new MockLyraRegistry();
    exchangeAdapter = new MockBaseExchangeAdapter();
    listingManager = new ListingManager(lyraRegistry);

    vm.mockCall(
      address(lyraRegistry),
      abi.encodeWithSelector(ILyraRegistry.getMarketAddresses.selector, address(optionMarket)),
      abi.encode(
        ILyraRegistry.OptionMarketAddresses({
          liquidityPool: address(0),
          liquidityToken: address(0),
          greekCache: address(greekCache),
          optionMarket: address(optionMarket),
          optionMarketPricer: address(0),
          optionToken: address(0),
          poolHedger: address(0),
          shortCollateral: address(0),
          gwavOracle: address(0),
          quoteAsset: address(0),
          baseAsset: address(0)
        })
      )
    );

    vm.mockCall(
      address(lyraRegistry),
      abi.encodeWithSelector(ILyraRegistry.getGlobalAddress.selector, bytes32("EXCHANGE_ADAPTER")),
      abi.encode(address(exchangeAdapter))
    );
  }

  function mockDefaultBoard() public {
    uint[] memory strikeIds = new uint[](5);
    uint[] memory skewGWAVs = new uint[](5);
    IOptionMarket.Strike[] memory boardStrikes = new IOptionMarket.Strike[](5);
    IOptionGreekCache.StrikeGreeks[] memory strikeGreeks = new IOptionGreekCache.StrikeGreeks[](5);

    vm.mockCall(
      address(optionMarket),
      abi.encodeWithSelector(IOptionMarket.getBoardAndStrikeDetails.selector),
      abi.encode(
        IOptionMarket.OptionBoard({id: 0, expiry: block.timestamp + 1 weeks, iv: 1 ether, frozen: false, strikeIds: strikeIds}),
        boardStrikes,
        0,
        0,
        0
      )
    );

    vm.mockCall(
      address(greekCache),
      abi.encodeWithSelector(IOptionGreekCache.getBoardGreeksView.selector),
      abi.encode(
        IOptionGreekCache.BoardGreeksView({
          boardGreeks: IOptionGreekCache.NetGreeks({
            netDelta: 0,
            netStdVega: 0,
            netOptionValue: 0
          }),
          ivGWAV: 1 ether,
          strikeGreeks: strikeGreeks,
          skewGWAVs: skewGWAVs
        })
      )
    );
  }
}

contract ListingManagerTest is ListingManagerTestBase {
  ///////////
  // Setup //
  ///////////

  function testListingManagerSetup() public {
    assertEq(address(lyraRegistry.getMarketAddresses(address(0)).greekCache), address(0));
    assertEq(address(lyraRegistry.getMarketAddresses(address(optionMarket)).greekCache), address(greekCache));
    assertEq(lyraRegistry.getGlobalAddress(bytes32("EXCHANGE_ADAPTER")), address(exchangeAdapter));
    assertEq(lyraRegistry.getGlobalAddress(bytes32("EXCHANGEADAPTERR")), address(0));

    mockDefaultBoard();

    listingManager.getSortedBoardDetails(optionMarket, greekCache, 0);
  }
}
