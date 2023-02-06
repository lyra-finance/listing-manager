// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/ListingManager.sol";
import "./mocks/TODO_CLEANUP_Mocks.sol";
import "./utils/ListingManagerTestBase.sol";

contract ListingManagerTest is ListingManagerTestBase {
  ///////////
  // Setup //
  ///////////

  function testListingManagerSetup() public {
    assertEq(address(lyraRegistry.getMarketAddresses(address(0)).greekCache), address(0));
    assertEq(address(lyraRegistry.getMarketAddresses(address(optionMarket)).greekCache), address(greekCache));
    assertEq(lyraRegistry.getGlobalAddress(bytes32("EXCHANGE_ADAPTER")), address(exchangeAdapter));
    assertEq(lyraRegistry.getGlobalAddress(bytes32("EXCHANGEADAPTERR")), address(0));

    ListingManager.BoardDetails memory res = listingManager.getSortedBoardDetails(optionMarket, greekCache, 0);
    console.log(res.strikes[0].strikePrice);
    console.log(res.strikes[1].strikePrice);
    console.log(res.strikes[2].strikePrice);
    console.log(res.strikes[3].strikePrice);
    console.log(res.strikes[4].strikePrice);
  }
}
