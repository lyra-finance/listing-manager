// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../../../src/TODO_CLEANUP_Interfaces.sol";

contract LyraRegistryMockSetup is Test {
  function setUpLyraRegistryMock(
    ILyraRegistry lyraRegistry,
    IOptionMarket optionMarket,
    IOptionGreekCache greekCache,
    IBaseExchangeAdapter exchangeAdapter
  ) public {
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
}
