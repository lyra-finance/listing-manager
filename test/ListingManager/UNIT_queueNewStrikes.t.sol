//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";

// import lib for next friday
import "../../src/lib/ExpiryGenerator.sol";

contract ListingManager_queueNewStrikes_Test is ListingManagerTestBase {
  /////////////////////////////////
  // findAndQueueStrikesForBoard //
  /////////////////////////////////

  // TODO: list out exhaustive test cases
  function testFindAndQueueStrikesForBoard() public {
    listingManager.findAndQueueStrikesForBoard(1);
  }

  ///////////////////////////
  // _executeQueuedStrikes //
  ///////////////////////////

  // TODO: list out exhaustive test cases
  function testExecuteQueuedStrikes() public {
    listingManager.findAndQueueStrikesForBoard(1);
    listingManager.setQueueParams(0, 0, 365 days);
    assertEq(listingManager.getQueuedStrikes(1).strikesToAdd.length, 18);
    listingManager.executeQueuedStrikes(1, 1);
    assertEq(listingManager.getQueuedStrikes(1).strikesToAdd.length, 17);
    listingManager.executeQueuedStrikes(1, 100);
    assertEq(listingManager.getQueuedStrikes(1).strikesToAdd.length, 0);
  }


  function testFastForwardStrikeUpdate() public {
    listingManager.findAndQueueStrikesForBoard(1);
    listingManager.setQueueParams(0, 0, 365 days);
    assertEq(listingManager.getQueuedStrikes(1).strikesToAdd.length, 14);
    vm.prank(riskCouncil);
    listingManager.fastForwardStrikeUpdate(1, 100);
    assertEq(listingManager.getQueuedStrikes(1).strikesToAdd.length, 0);
  }
}
