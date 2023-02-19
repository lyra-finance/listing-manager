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
    (, ListingManager.StrikeToAdd[] memory res) = listingManager.TEST_getNewBoardData(block.timestamp + 2 weeks);
  }

  function testQueueStrikesForBoard() public {
    listingManager.findAndQueueStrikesForBoard(1);
  }

  function testCreateAndAddNewBoard() public {
    uint expiry = block.timestamp + 4 weeks;
    expiry = ExpiryGenerator._getNextFriday(expiry);
    listingManager.queueNewBoard(expiry);
    (, ListingManager.StrikeToAdd[] memory strikes) = listingManager.TEST_getNewBoardData(expiry);
    
    assertEq(strikes.length, 11); // why 11?
  }
}
