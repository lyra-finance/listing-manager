//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../src/ListingManager.sol";
import "./mocks/LyraContractMocks.sol";
import "./utils/ListingManagerTestBase.sol";
import "src/lib/ExpiryGenerator.sol";

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

  function testCreateAndAddNewBoard() public {
    uint expiry = block.timestamp + 2 weeks;
    expiry = ExpiryGenerator.getNextFriday(expiry);
    listingManager.queueNewBoard(expiry);
    (, ListingManager.StrikeToAdd[] memory strikes) = listingManager.TEST_getNewBoardData(expiry);

    assertEq(strikes.length, 15);
  }

  function testGetMissingExpiries() public {
    uint[] memory missingExpiries = listingManager.getAllMissingExpiries();
    for (uint i = 0; i < missingExpiries.length; i++) {
      listingManager.queueNewBoard(missingExpiries[i]);
    }
    ListingManager.QueuedBoard[] memory allQueuedBoards = listingManager.getAllQueuedBoards();
    for (uint i = 0; i < allQueuedBoards.length; i++) {
      assertEq(allQueuedBoards[i].expiry, missingExpiries[allQueuedBoards.length - i - 1]);
    }
  }

  function testGetState() public {
    listingManager.getListingManagerState();
  }
}
