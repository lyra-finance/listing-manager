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
    uint expiryToQueue = ExpiryGenerator.getNextFriday(block.timestamp + 1 weeks);
    listingManager.queueNewBoard(expiryToQueue);
  }

  function testQueueStrikesForBoard() public {
    listingManager.findAndQueueStrikesForBoard(1);
  }
}
