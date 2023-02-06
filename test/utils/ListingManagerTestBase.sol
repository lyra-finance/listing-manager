// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../src/ListingManager.sol";
import "../mocks/TODO_CLEANUP_Mocks.sol";
import "./setupMocks/LyraRegistryMockSetup.sol";
import "./setupMocks/OptionMarketMockSetup.sol";

contract ListingManagerTestBase is Test, LyraRegistryMockSetup, OptionMarketMockSetup {
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

    LyraRegistryMockSetup.setUpLyraRegistryMock(lyraRegistry, optionMarket, greekCache, exchangeAdapter);
    OptionMarketMockSetup.mockDefaultBoard(optionMarket, greekCache);
  }
}
