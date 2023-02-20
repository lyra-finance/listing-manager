//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";

contract ListingManager_OptionMarketViews_Test is ListingManagerTestBase {
  /////////////////////
  // getBoardDetails //
  /////////////////////

  // TODO: exhaustive test writeup
  function testGetBoardDetails() public {
    ListingManager.BoardDetails memory boardDetails = listingManager.getBoardDetails(1);
    console.log('expiry', boardDetails.expiry);
    console.log('baseIv', boardDetails.baseIv);
  }

  ////////////////////////
  // getAllBoardDetails //
  ////////////////////////

  // TODO: exhaustive test writeup
  function testGetAllBoardDetails() public {
    listingManager.getAllBoardDetails();
  }

  ////////////////
  // isCBActive //
  ////////////////

  function testCBIsActive() public {
    vm.mockCall(address(liquidityPool), abi.encodeWithSelector(ILiquidityPool.CBTimestamp.selector), abi.encode(block.timestamp + 4 weeks));
    assertEq(listingManager.TEST_isCBActive(), true);
  }

  function testCBIsNotActive() public {
    vm.mockCall(address(liquidityPool), abi.encodeWithSelector(ILiquidityPool.CBTimestamp.selector), abi.encode(0));
    assertEq(listingManager.TEST_isCBActive(), false);
  }
}
