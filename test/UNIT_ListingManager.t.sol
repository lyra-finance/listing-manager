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
    uint[] memory newStrikes = new uint[](5);
    newStrikes[0] = 1200 ether;
    newStrikes[1] = 1300 ether;
    newStrikes[2] = 1400 ether;
    newStrikes[3] = 1500 ether;
    newStrikes[4] = 1600 ether;

    ListingManager.QueuedBoard memory res = listingManager.TEST_getNewBoardData(block.timestamp + 2 weeks, newStrikes);
  }
}
