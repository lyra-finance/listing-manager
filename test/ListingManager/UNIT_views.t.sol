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
    assertEq(queued.strikesToAdd.length, 12, "length of strikes does not match expected");
  }

  function testCannotGetDeletedQueuedBoard() public {
    uint expiry = addBoardWithStrikes();
    ListingManager.QueuedBoard memory queued = listingManager.getQueuedBoard(expiry);
    assertEq(queued.expiry, ExpiryGenerator.getNextFriday(block.timestamp) + 1 weeks);
    assertEq(queued.strikesToAdd.length, 12, "length of strikes does not match expected");

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
    // get the live board from mock option market contract
    uint[] memory liveBoards = optionMarket.getLiveBoards();

    ListingManager.QueuedStrikes memory queuedStrikes = listingManager.getQueuedStrikes(liveBoards[0]);

    assertEq(queuedStrikes.strikesToAdd.length, 0, "strikes already queued");

    // added strikes to live board
    listingManager.findAndQueueStrikesForBoard(liveBoards[0]);
    ListingManager.QueuedStrikes memory curQueuedStrikes = listingManager.getQueuedStrikes(liveBoards[0]);

    assertGt(curQueuedStrikes.strikesToAdd.length, queuedStrikes.strikesToAdd.length, "strikes not queued");
  }

  function testGetDeletedQueuedStrikes() public {
    // get the live board from mock option market contract
    uint[] memory liveBoards = optionMarket.getLiveBoards();

    ListingManager.QueuedStrikes memory queuedStrikes = listingManager.getQueuedStrikes(liveBoards[0]);

    assertEq(queuedStrikes.strikesToAdd.length, 0, "strikes already queued");

    // added strikes to live board
    listingManager.findAndQueueStrikesForBoard(liveBoards[0]);
    ListingManager.QueuedStrikes memory curQueuedStrikes = listingManager.getQueuedStrikes(liveBoards[0]);

    assertGt(curQueuedStrikes.strikesToAdd.length, queuedStrikes.strikesToAdd.length, "strikes not queued");
    assertEq(curQueuedStrikes.boardId, liveBoards[0], "board id not set");
    assertGt(curQueuedStrikes.queuedTime, 0, "queued time not set");
    vm.prank(riskCouncil);
    listingManager.vetoStrikeUpdate(liveBoards[0]);

    curQueuedStrikes = listingManager.getQueuedStrikes(liveBoards[0]);

    assertEq(curQueuedStrikes.strikesToAdd.length, 0, "strikes not deleted");
    assertEq(curQueuedStrikes.boardId, 0, "board id not nulled");
    assertEq(curQueuedStrikes.queuedTime, 0, "queued time not nulled");
  }

  // helpers
  function addBoardWithStrikes() internal returns (uint expiry) {
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
