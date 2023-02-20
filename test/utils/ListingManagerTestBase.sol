//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../src/ListingManager.sol";
import "../mocks/LyraContractMocks.sol";
import "./setupMocks/OptionMarketMockSetup.sol";
import "./testContracts/TestListingManager.sol";

contract ListingManagerTestBase is Test, OptionMarketMockSetup {
  IOptionGreekCache greekCache;
  IOptionMarket optionMarket;
  ILiquidityPool liquidityPool;
  IBaseExchangeAdapter exchangeAdapter;
  IOptionMarketGovernanceWrapper governanceWrapper;
  TestListingManager listingManager;
  address riskCouncil = address(0xbee);

  constructor() {
    vm.warp(1600000000);
  }

  function setUp() public {
    greekCache = new MockOptionGreekCache();
    optionMarket = new MockOptionMarket();
    exchangeAdapter = new MockBaseExchangeAdapter();
    liquidityPool = new MockLiquidityPool();
    governanceWrapper = new MockOptionMarketGovernanceWrapper();

    listingManager = new TestListingManager(exchangeAdapter, liquidityPool, greekCache, optionMarket, governanceWrapper);
    listingManager.setRiskCouncil(riskCouncil);

    OptionMarketMockSetup.mockDefaultBoard(optionMarket, greekCache);
    mockSpotPrice(1500 ether);
  }

  function mockSpotPrice(uint spotPrice) internal {
    vm.mockCall(
      address(exchangeAdapter),
      abi.encodeWithSelector(IBaseExchangeAdapter.getSpotPriceForMarket.selector),
      abi.encode(spotPrice)
    );
  }
}
