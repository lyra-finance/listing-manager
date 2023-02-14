//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../src/ListingManager.sol";
import "./mocks/LyraContractMocks.sol";
import "./utils/ListingManagerTestBase.sol";

contract ListingManagerTest is ListingManagerTestBase {
  ///////////
  // Setup //
  ///////////

  function testGetNewBoardData() public {
    console.log("hi");

    ListingManager.QueuedBoard memory res = listingManager.TEST_getNewBoardData(block.timestamp + 2 weeks);
  }
}
