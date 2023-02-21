//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";
import "src/lib/ExpiryGenerator.sol";

contract ListingManager_fetchSurroundingBoards_Test is ListingManagerTestBase {
  ////////////////////////////
  // fetchSurroundingBoards //
  ////////////////////////////
  /**
   * TODO: implement testcases:
   * Expiry on short edge:
   * 1. two boards, in order -> first index is shortDated, nothing for longDated
   * 2. two boards, out of order -> second index is shortDated, nothing for longDated
   * 3. two boards, same expiry (different to passed in expiry) -> first index is shortDated
   * 4. one board, shortDated will be the result
   * Expiry on long edge:
   * same 4 cases, just returns longDated and not shortDated
   * Expiry in the middle:
   * one on one side, two on the other, out of order - twice
   * Misc:
   * boardDetails length of 0 - reverts
   * boardDetails has same expiry as requested - reverts
   */
  function testFetchSurroundingBoards() public {
    ListingManager.BoardDetails[] memory details;
    listingManager.TEST_fetchSurroundingBoards(details, 12000);

    

  }
}
