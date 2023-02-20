//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";

// import lib for next friday
import "../../src/lib/ExpiryGenerator.sol";

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
  function testGetNewBoardData() public {}

  ////////////////////
  // _queueNewBoard //
  ////////////////////

  // - cb reverts queueing
  // - reverts if invalid expiry (too short/not weekly/not monthly)
  // - reverts if board already queued
  // - successfully queues (check state after)
  function testQueueNewBoard() public {
    // set the CB to revert
    uint expiry = ExpiryGenerator.getNextFriday(block.timestamp);
    vm.mockCall(address(liquidityPool), abi.encodeWithSelector(ILiquidityPool.CBTimestamp.selector), abi.encode(block.timestamp + 4 weeks));
    vm.expectRevert('CB active');   
    listingManager.queueNewBoard(expiry);

    // // set the CB to not revert
    vm.mockCall(address(liquidityPool), abi.encodeWithSelector(ILiquidityPool.CBTimestamp.selector), abi.encode(0));
    expiry = expiry - 2 weeks;
    vm.expectRevert('expiry too short');
    listingManager.queueNewBoard(expiry);

    // should revert, expiry not a friday
    expiry = expiry + 4 weeks + 1 days;
    vm.expectRevert('expiry doesn\'t match format');
    listingManager.queueNewBoard(expiry);

    // sucessfully queue board
    expiry = ExpiryGenerator.getNextFriday(block.timestamp + 2 weeks);
    listingManager.queueNewBoard(expiry);

    // should revert, board already queued
    vm.expectRevert('board already queued');
    listingManager.queueNewBoard(expiry);

    // check the board is queued
    ListingManager.QueuedBoard memory queued = listingManager.getQueuedBoard(expiry);
    assertEq(queued.expiry, expiry);
  }
}
