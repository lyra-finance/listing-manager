//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";

contract ListingManager_OptionMarketViews_Test is ListingManagerTestBase {
  /////////////////////
  // getBoardDetails //
  /////////////////////

  // TODO: exhaustive test writeup
  function testGetBoardDetails() public {
    listingManager.getBoardDetails(1);
  }

  ////////////////////////
  // getAllBoardDetails //
  ////////////////////////

  // TODO: exhaustive test writeup
  function testGetAllBoardDetails() public {
    listingManager.getAllBoardDetails();
  }
}
