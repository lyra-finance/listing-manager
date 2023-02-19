//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";

contract ListingManager_queueNewBoard_Test is ListingManagerTestBase {
  ///////////////////////
  // _interpolateBoard //
  ///////////////////////

  // TODO: test cases

  function testInterpolateBoardShortExpiry() public {
    // TODO: interpolates correctly for short expiry (1d)
    // - 3 strikes (OTM,ATM,ITM)
    assertTrue(false);
  }

  function testInterpolateBoardLongExpiry() public {
    // TODO: interpolates correctly for long expiry (12w)
    // - 3 strikes (OTM,ATM,ITM)
    assertTrue(false);
  }

  function testInterpolateBoardZeroStrikes() public {
    // TODO: works for 0 strikes
    assertTrue(false);
  }

  function FUZZ_testInterpolateBoard() public {
    // TODO: fuzz test (3 strikes per board, OTM, ATM, ITM):
    //   - lower skew <= generated skew <= upper skew for the same strikes
    assertTrue(false);
  }

  ///////////////////////
  // _extrapolateBoard //
  ///////////////////////

  function testExtrapolateBoardShortExpiryShorterBoard() public {
    // TODO: extrapolating a 1 day expiry board from a 6 hr expiry board
    // - 3 strikes (OTM,ATM,ITM)
  }
  function testExtrapolateBoardShortExpiryLongerBoard() public {
    // TODO: extrapolating a 1 day expiry board from a 1 week expiry board
    // - 3 strikes (OTM,ATM,ITM)
  }

  function testExtrapolateBoardLongExpiryShorterBoard() public {
    // TODO: extrapolating a 12w expiry board from a 10w expiry board
    // - 3 strikes (OTM,ATM,ITM)
  }

  function testExtrapolateBoardLongExpiryLongerBoard() public {
    // TODO: extrapolating a 12w expiry board from a 14w expiry board
    // - 3 strikes (OTM,ATM,ITM)
  }

  function testExtrapolateBoardZeroStrikes() public {
    // TODO: works for 0 strikes
  }

  function FUZZ_extrapolateShorterBoard() public {
    // TODO: fuzz test:
    // - 3 strikes (OTM,ATM,ITM)
    // - 3 skews generated are >= same strikes from a longer dated board
  }

  function FUZZ_extrapolateLongerBoard() public {
    // TODO: fuzz test:
    // - 3 strikes (OTM,ATM,ITM)
    // - 3 skews generated are <= same strikes from a longer dated board
  }

  //////////////////////
  // _getNewBoardData //
  //////////////////////

  // TODO: implement tests:
  // - hit all 3 coverage branches
  // - correct number of strikes generated
  function getNewBoardData() public {}

  ////////////////////
  // _queueNewBoard //
  ////////////////////

  // TODO: implement tests:
  // - cb reverts queueing
  // - reverts if invalid expiry (too short/not weekly/not monthly)
  // - reverts if board already queued
  // - successfully queues (check state after)
  function queueNewBoard() public {}
}
