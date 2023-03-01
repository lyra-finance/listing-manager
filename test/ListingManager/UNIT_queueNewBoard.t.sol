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

  function testInterpolateBoardShortExpiry() public {
    // interpolates correctly for short expiry (1d)
    // - 3 strikes (OTM,ATM,ITM)
    OptionMarketMockSetup.mockBoardWithThreeStrikes(
      optionMarket, greekCache, ExpiryGenerator.getNextFriday(block.timestamp + 2 weeks)
    );
    // live board's expiry is 2 weeks away
    uint expiry = ExpiryGenerator.getNextFriday(block.timestamp + 1 weeks);
    listingManager.queueNewBoard(expiry);
    (, ListingManager.StrikeToAdd[] memory strikes) = listingManager.TEST_getNewBoardData(expiry);

    assertEq(strikes.length, 12);
    assertEq(strikes[0].strikePrice, 1300 ether, "atm strike missing");
    assertEq(strikes[0].skew, 1 * 1e18, "ATM strike skew not equal to 1");

    assertGt(strikes[1].skew, strikes[0].skew, "ITM strike not less than ATM");
    assertLt(strikes[2].skew, strikes[0].skew, "OTM strike not greater than ATM");
  }

  function testInterpolateBoardLongExpiry() public {
    // TODO: interpolates correctly for long expiry (12w)
    // - 3 strikes (OTM,ATM,ITM)
    OptionMarketMockSetup.mockBoardWithThreeStrikes(
      optionMarket, greekCache, ExpiryGenerator.getNextFriday(block.timestamp + 13 weeks)
    );
    // live board's expiry is 2 week away
    uint expiry = ExpiryGenerator.getNextFriday(block.timestamp + 12 weeks);
    listingManager.queueNewBoard(expiry);
    (, ListingManager.StrikeToAdd[] memory strikes) = listingManager.TEST_getNewBoardData(expiry);

    assertEq(strikes.length, 12);

    assertEq(strikes[0].strikePrice, 1300 ether, "atm strike missing");
    assertEq(strikes[0].skew, 1 * 1e18, "ATM strike skew not equal to 1");

    assertGt(strikes[1].skew, strikes[0].skew, "ITM strike not less than ATM");
    assertLt(strikes[2].skew, strikes[0].skew, "OTM strike not greater than ATM");
  }

  // This will throw if when a board with zero strikes is meant to be extrapolated form
  function testRevertInterpolateBoardZeroStrikes() public {
    // TODO: works for 0 strikes
    vm.warp(1674806400);
    uint expiry = ExpiryGenerator.getNextFriday(block.timestamp + 13 weeks);
    OptionMarketMockSetup.mockBoardWithZeroStrikes(optionMarket, greekCache, expiry);
    // live board's expiry is 2 week away
    expiry = ExpiryGenerator.getNextFriday(block.timestamp + 12 weeks);
    vm.expectRevert();
    listingManager.queueNewBoard(expiry);
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
    vm.warp(1674806400);
    OptionMarketMockSetup.mockBoardWithThreeStrikes(
      optionMarket, greekCache, ExpiryGenerator.getNextFriday(block.timestamp + 1 weeks)
    );
    // live board's expiry is 2 weeks away
    vm.warp(block.timestamp + 1 weeks + 4 days);
    uint expiry = ExpiryGenerator.getNextFriday(block.timestamp);
    listingManager.queueNewBoard(expiry);
    (, ListingManager.StrikeToAdd[] memory strikes) = listingManager.TEST_getNewBoardData(expiry);

    assertEq(strikes.length, 15);
    assertEq(strikes[0].strikePrice, 1300 ether, "atm strike missing");
    assertEq(strikes[0].skew, 1 * 1e18, "ATM strike skew not equal to 1");

    assertGt(strikes[1].skew, strikes[0].skew, "ITM strike not less than ATM");
    assertLt(strikes[2].skew, strikes[0].skew, "OTM strike not greater than ATM");
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

  function testFUZZ_extrapolateShorterBoard(uint expiryOffset) public {
    // TODO: fuzz test:
    // - 3 strikes (OTM,ATM,ITM)
    // - 3 skews generated are >= same strikes from a longer dated board
    vm.warp(1674806400);
    vm.assume(expiryOffset < 30 weeks && expiryOffset > 2 weeks);
    uint targetExpiry = block.timestamp + expiryOffset;
    OptionMarketMockSetup.mockBoardWithThreeStrikes(
      optionMarket, greekCache, ExpiryGenerator.getNextFriday(block.timestamp + 1 weeks)
    );

    // live board's expiry is 2 weeks away
    uint expiry = ExpiryGenerator.getNextFriday(targetExpiry);
    listingManager.queueNewBoard(expiry);
    (, ListingManager.StrikeToAdd[] memory strikes) = listingManager.TEST_getNewBoardData(expiry);

    assertGt(strikes.length, 8);
    assertEq(strikes[0].strikePrice, 1300 ether, "atm strike missing");
    assertEq(strikes[0].skew, 1 * 1e18, "ATM strike skew not equal to 1");

    assertGt(strikes[1].skew, strikes[0].skew, "ITM strike not less than ATM");
    assertLt(strikes[2].skew, strikes[0].skew, "OTM strike not greater than ATM");
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
  function testQueueNewBoard() public {
    // set the CB to revert
    uint expiry = ExpiryGenerator.getNextFriday(block.timestamp);
    vm.mockCall(
      address(liquidityPool),
      abi.encodeWithSelector(ILiquidityPool.CBTimestamp.selector),
      abi.encode(block.timestamp + 4 weeks)
    );
    vm.expectRevert(abi.encodeWithSelector(ListingManager.LM_CBActive.selector, block.timestamp));
    listingManager.queueNewBoard(expiry);

    // set the CB to not revert
    vm.mockCall(address(liquidityPool), abi.encodeWithSelector(ILiquidityPool.CBTimestamp.selector), abi.encode(0));
    expiry = expiry - 2 weeks;
    vm.expectRevert(abi.encodeWithSelector(ListingManager.LM_ExpiryTooShort.selector, expiry, 7 days));
    listingManager.queueNewBoard(expiry);

    // should revert, expiry not a friday
    expiry = expiry + 4 weeks + 1 days;
    vm.expectRevert(abi.encodeWithSelector(ListingManager.LM_ExpiryDoesntMatchFormat.selector, expiry));
    listingManager.queueNewBoard(expiry);

    // sucessfully queue board
    expiry = ExpiryGenerator.getNextFriday(block.timestamp + 2 weeks);
    listingManager.queueNewBoard(expiry);

    // should revert, board already queued
    vm.expectRevert(abi.encodeWithSelector(ListingManager.LM_BoardAlreadyQueued.selector, expiry));
    listingManager.queueNewBoard(expiry);

    // check the board is queued
    ListingManager.QueuedBoard memory queued = listingManager.getQueuedBoard(expiry);
    assertEq(queued.expiry, expiry);
  }

  /////////////////////////
  // _executeQueuedBoard //
  /////////////////////////
  function testExecuteQueuedBoard() public {
    uint expiry = ExpiryGenerator.getNextFriday(block.timestamp + 2 weeks);
    listingManager.queueNewBoard(expiry);

    listingManager.setQueueParams(0, 0, 10);
    vm.warp(block.timestamp + 100);

    vm.expectEmit(false, false, false, false);
    emit LM_QueuedBoardStale(address(0), 0, 0, 0);
    listingManager.executeQueuedBoard(expiry);

    vm.expectRevert(abi.encodeWithSelector(ListingManager.LM_BoardNotQueued.selector, expiry));
    listingManager.executeQueuedBoard(expiry);

    listingManager.queueNewBoard(expiry);

    vm.expectEmit(false, false, false, false);
    emit LM_QueuedBoardStale(address(0), 0, 0, 0);
    listingManager.executeQueuedBoard(expiry);
  }

  event LM_QueuedBoardStale(address indexed caller, uint indexed expiry, uint staleTimestamp, uint blockTime);
  event LM_QueuedBoardExecuted(address indexed caller, uint indexed expiry, ListingManager.QueuedBoard board);
}
