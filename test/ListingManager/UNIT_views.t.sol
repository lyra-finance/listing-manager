//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";

contract ListingManager_Views_Test is ListingManagerTestBase {
  /////////////////////
  // getBoardDetails //
  /////////////////////

  function testGetQueuedBoard() public {
    uint expiry = addBoardWithStrikes();
    ListingManager.QueuedBoard memory queued = listingManager.getQueuedBoard(expiry);
    assertEq(queued.expiry, ExpiryGenerator.getNextFriday(block.timestamp) + 1 weeks);
    assertEq(queued.strikesToAdd.length, 13, "length of strikes does not match expected");    
  }

  function testCannotGetDeletedQueuedBoard() public {
    uint expiry = addBoardWithStrikes();
    ListingManager.QueuedBoard memory queued = listingManager.getQueuedBoard(expiry);
    assertEq(queued.expiry, ExpiryGenerator.getNextFriday(block.timestamp) + 1 weeks);
    assertEq(queued.strikesToAdd.length, 13, "length of strikes does not match expected");  

    // veto Board
    vm.prank(riskCouncil);
    listingManager.vetoQueuedBoard(expiry);
    ListingManager.QueuedBoard memory dequeued = listingManager.getQueuedBoard(expiry);

    assertEq(dequeued.expiry, 0);
    assertEq(dequeued.strikesToAdd.length, 0, "length of strikes does not match expected"); 
    assertEq(dequeued.baseIv, 0); 
  }

  ////////////////////////
  // getAllBoardDetails //
  ////////////////////////

  function testGetQueuedStrikes() public {
    // TODO: get queued strikes for a board, and assert data is correct
    assertTrue(false);
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

  //////////////////////
  // getValidExpiries //
  //////////////////////
  function testGetValidExpiries() public {
    uint[] memory validExpiries = listingManager.getValidExpiries();
    console.log("Valid expiries:");
    for (uint i = 0; i < validExpiries.length; i++) {
      console.log("-", validExpiries[i]);
    }
    // TODO: vm.warp to specific times to test?
  }
}
