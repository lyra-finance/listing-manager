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
    listingManager.getQueuedBoard(1);
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
