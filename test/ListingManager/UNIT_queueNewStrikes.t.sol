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

    ListingManager.QueuedStrikes[] memory queuedStrikes = listingManager.getAllQueuedStrikes();
    assertEq(queuedStrikes.length, 1);
    assertEq(queuedStrikes[0].strikesToAdd.length, 14);
  }

  ///////////////////////////
  // _executeQueuedStrikes //
  ///////////////////////////

  function testExecuteQueuedStrikes() public {
    listingManager.findAndQueueStrikesForBoard(1);
    listingManager.setQueueParams(0, 0, 365 days);
    assertEq(listingManager.getQueuedStrikes(1).strikesToAdd.length, 14);
    listingManager.executeQueuedStrikes(1, 1);
    assertEq(listingManager.getQueuedStrikes(1).strikesToAdd.length, 13);
    listingManager.executeQueuedStrikes(1, 100);
    assertEq(listingManager.getQueuedStrikes(1).strikesToAdd.length, 0);
  }

  function testCannotExecuteStrikeWhenCBActive() public {
    listingManager.findAndQueueStrikesForBoard(1);
    listingManager.setQueueParams(0, 0, 365 days);
    vm.mockCall(address(liquidityPool), abi.encodeWithSignature("CBTimestamp()"), abi.encode(block.timestamp + 5 weeks));
    listingManager.executeQueuedStrikes(1, 1);
    ListingManager.QueuedStrikes memory queStrikes = listingManager.getQueuedStrikes(1);
    assertEq(queStrikes.strikesToAdd.length, 0);
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
