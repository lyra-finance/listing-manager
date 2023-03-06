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
   * Expiry on short edge:
   * 1. two boards, in order -> first index is shortDated, nothing for longDated
   * 2. two boards, out of order -> second index is shortDated, nothing for longDated
   * 3. two boards, same expiry (different to passed in expiry) -> first index is shortDated
   * 4. one board, shortDated will be the result
   * Expiry on long edge:
   * same 4 cases, just returns longDated and not shortDated
   */
  function testFetchSurroundingBoardsShortDated() public {
    // Closest expiry is shortDated only

    vm.warp(0);
    uint testExpiry = 20000;
    uint closerExpiry = 19000;
    uint furtherExpiry = 18000;

    VolGenerator.Board memory shortDated;
    VolGenerator.Board memory longDated;

    ////
    // first expiry is closer
    (shortDated, longDated) =
      listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(closerExpiry, furtherExpiry), testExpiry);
    assertEq(shortDated.baseIv, 1 ether);
    assertEq(longDated.baseIv, 0);

    ////
    // second expiry is closer
    (shortDated, longDated) =
      listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(furtherExpiry, closerExpiry), testExpiry);
    assertEq(shortDated.baseIv, 2 ether);
    assertEq(longDated.baseIv, 0);

    ////
    // both expiries the same
    (shortDated, longDated) =
      listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(closerExpiry, closerExpiry), testExpiry);
    assertEq(shortDated.baseIv, 1 ether); // it will always be the first seen
    assertEq(longDated.baseIv, 0);

    ////
    // only one board
    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(closerExpiry), testExpiry);
    assertEq(shortDated.baseIv, 1 ether);
    assertEq(longDated.baseIv, 0);
  }

  function testFetchSurroundingBoardsLongerDated() public {
    // Closest expiry is longDated only

    vm.warp(0);
    uint testExpiry = 20000;
    uint closerExpiry = 21000;
    uint furtherExpiry = 22000;

    VolGenerator.Board memory shortDated;
    VolGenerator.Board memory longDated;

    ////
    // first expiry is closer
    (shortDated, longDated) =
      listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(closerExpiry, furtherExpiry), testExpiry);
    assertEq(shortDated.baseIv, 0);
    assertEq(longDated.baseIv, 1 ether);

    ////
    // second expiry is closer
    (shortDated, longDated) =
      listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(furtherExpiry, closerExpiry), testExpiry);
    assertEq(shortDated.baseIv, 0);
    assertEq(longDated.baseIv, 2 ether);

    ////
    // both expiries the same
    (shortDated, longDated) =
      listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(closerExpiry, closerExpiry), testExpiry);
    assertEq(shortDated.baseIv, 0);
    assertEq(longDated.baseIv, 1 ether); // it will always be the first seen

    ////
    // only one board
    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(closerExpiry), testExpiry);
    assertEq(shortDated.baseIv, 0);
    assertEq(longDated.baseIv, 1 ether);
  }

  function testFetchSurroundingBoardsInMiddle() public {
    vm.warp(0);
    uint shortestExpiry = 18000;
    uint shorterExpiry = 19000;
    uint longerExpiry = 21000;
    uint longestExpiry = 22000;

    VolGenerator.Board memory shortDated;
    VolGenerator.Board memory longDated;

    ////
    // middle is shorter expiry, several combinations
    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(
      getBoardDetailsArray(shortestExpiry, longerExpiry, longestExpiry), shorterExpiry
    );
    assertEq(shortDated.baseIv, 1 ether);
    assertEq(longDated.baseIv, 2 ether);

    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(
      getBoardDetailsArray(longerExpiry, longestExpiry, shortestExpiry), shorterExpiry
    );
    assertEq(shortDated.baseIv, 3 ether);
    assertEq(longDated.baseIv, 1 ether);

    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(
      getBoardDetailsArray(longestExpiry, shortestExpiry, longerExpiry), shorterExpiry
    );
    assertEq(shortDated.baseIv, 2 ether);
    assertEq(longDated.baseIv, 3 ether);

    ////
    // middle is longer expiry, several combinations
    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(
      getBoardDetailsArray(shortestExpiry, shorterExpiry, longestExpiry), longerExpiry
    );
    assertEq(shortDated.baseIv, 2 ether);
    assertEq(longDated.baseIv, 3 ether);

    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(
      getBoardDetailsArray(shorterExpiry, longestExpiry, shortestExpiry), longerExpiry
    );
    assertEq(shortDated.baseIv, 1 ether);
    assertEq(longDated.baseIv, 2 ether);

    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(
      getBoardDetailsArray(longestExpiry, shortestExpiry, shorterExpiry), longerExpiry
    );
    assertEq(shortDated.baseIv, 3 ether);
    assertEq(longDated.baseIv, 1 ether);
  }

  function testFetchSurroundingBoardsMisc() public {
    vm.warp(0);
    uint shorterExpiry = 19000;
    uint testExpiry = 20000;

    VolGenerator.Board memory shortDated;
    VolGenerator.Board memory longDated;

    ListingManager.BoardDetails[] memory boardDetails;

    // boardDetails length of 0 - reverts
    boardDetails = new ListingManager.BoardDetails[](0);
    vm.expectRevert(ListingManager.LM_NoBoards.selector); // arithmetic error, subtracting 1 from strikes.length
    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(boardDetails, testExpiry);

    // strikeDetails length of 0 - reverts
    boardDetails = new ListingManager.BoardDetails[](1);
    boardDetails[0] = ListingManager.BoardDetails({
      expiry: shorterExpiry,
      baseIv: 1 ether,
      strikes: new ListingManager.StrikeDetails[](0)
    });

    vm.expectRevert(abi.encodeWithSelector(ListingManager.LM_BoardHasNoStrikes.selector, shorterExpiry));
    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(boardDetails, testExpiry);

    // boardDetails has same expiry as requested - reverts
    vm.expectRevert(abi.encodeWithSelector(ListingManager.LM_ExpiryExists.selector, testExpiry));
    (shortDated, longDated) = listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(testExpiry), testExpiry);

    // boardDetails of matched board is expired - reverts
    vm.warp(shorterExpiry + 1);
    vm.expectRevert(abi.encodeWithSelector(ListingManager.LM_BoardExpired.selector, shorterExpiry, shorterExpiry + 1));
    (shortDated, longDated) =
      listingManager.TEST_fetchSurroundingBoards(getBoardDetailsArray(shorterExpiry), testExpiry);
  }
  ///////////
  // Utils //
  ///////////

  function getBoardDetailsArray(uint expiry1) internal returns (ListingManager.BoardDetails[] memory) {
    ListingManager.BoardDetails[] memory res = new ListingManager.BoardDetails[](1);
    res[0] = ListingManager.BoardDetails({
      expiry: expiry1,
      baseIv: 1 ether,
      // Note: board needs at least one strike, otherwise sorting the strikes fails
      strikes: new ListingManager.StrikeDetails[](1)
    });
    return res;
  }

  function getBoardDetailsArray(uint expiry1, uint expiry2) internal returns (ListingManager.BoardDetails[] memory) {
    ListingManager.BoardDetails[] memory res = new ListingManager.BoardDetails[](2);
    res[0] = ListingManager.BoardDetails({
      expiry: expiry1,
      baseIv: 1 ether,
      // Note: board needs at least one strike, otherwise sorting the strikes fails
      strikes: new ListingManager.StrikeDetails[](1)
    });
    res[1] =
      ListingManager.BoardDetails({expiry: expiry2, baseIv: 2 ether, strikes: new ListingManager.StrikeDetails[](1)});
    return res;
  }

  function getBoardDetailsArray(
    uint expiry1,
    uint expiry2,
    uint expiry3
  ) internal returns (ListingManager.BoardDetails[] memory) {
    ListingManager.BoardDetails[] memory res = new ListingManager.BoardDetails[](3);
    res[0] = ListingManager.BoardDetails({
      expiry: expiry1,
      baseIv: 1 ether,
      // Note: board needs at least one strike, otherwise sorting the strikes fails
      strikes: new ListingManager.StrikeDetails[](1)
    });
    res[1] =
      ListingManager.BoardDetails({expiry: expiry2, baseIv: 2 ether, strikes: new ListingManager.StrikeDetails[](1)});
    res[2] =
      ListingManager.BoardDetails({expiry: expiry3, baseIv: 3 ether, strikes: new ListingManager.StrikeDetails[](1)});
    return res;
  }
}
