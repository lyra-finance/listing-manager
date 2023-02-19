//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";

contract ListingManager_toVolGeneratorBoard_Test is ListingManagerTestBase {
  /////////////////////
  // getBoardDetails //
  /////////////////////

  /**
   * TODO:
   * Tests:
   * 1. pass in a board with unsorted strikes, make sure output is correct
   * 2. pass in a board with sorted strikes
   * 3. board with no strikes ?
   * 4. expiry < block.timestamp
   */
  function testToVolGeneratorBoard() public {}
}
