//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";

contract ListingManager_Views_Test is ListingManagerTestBase {
  /////////////////////
  // getBoardDetails //
  /////////////////////

  function testGetQueuedBoard() public {
    // TODO: get queued board with strikes and assert data is correct
    uint expiry= addBoardWithStrikes();
    ListingManager.QueuedBoard memory queued = listingManager.getQueuedBoard(expiry);
    assertEq(queued.expiry, ExpiryGenerator.getNextFriday(block.timestamp) + 1 weeks);
    assertGt(queued.strikesToAdd.length, 1);
    console.log('length of strikes added', queued.strikesToAdd.length);
  }

  function testGetDeletedQueuedBoard() public {
    // TODO: get queued board after deleting it
    assertTrue(false);
  }

  ////////////////////////
  // getAllBoardDetails //
  ////////////////////////

  function testGetQueuedStrikes() public {
    // TODO: get queued strikes for a board, and assert data is correct
    listingManager.getQueuedStrikes(1);
  }

  function testGetDeletedQueuedStrikes() public {
    // TODO: get queued strikes after deleting it

    assertTrue(false);
  }


  // helpers
  function addBoardWithStrikes() internal returns(uint expiry) {
    expiry = ExpiryGenerator.getNextFriday(block.timestamp) + 1 weeks;
    listingManager.queueNewBoard(expiry);
  }
}
