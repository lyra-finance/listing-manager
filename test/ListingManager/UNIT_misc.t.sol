//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../utils/ListingManagerTestBase.sol";

contract ListingManager_misc_Test is ListingManagerTestBase {
  /////////////////////
  // secToAnnualised //
  /////////////////////

  function testSecToAnnualised() public {
    assertEq(listingManager.TEST_secToAnnualized(0), 0);
    // Note: off by 1 as the division rounds down
    assertEq(listingManager.TEST_secToAnnualized(1), 0.000000031709791983 ether);
    assertEq(listingManager.TEST_secToAnnualized(1 days), 0.00273972602739726 ether);
    assertEq(listingManager.TEST_secToAnnualized(365 days), 1 ether);
    assertEq(listingManager.TEST_secToAnnualized(365 days * 3), 3 ether);
  }

  //////////////////////
  // quickSortStrikes //
  //////////////////////

  function testQuickSortStrikes() public {
    ListingManager.StrikeDetails[] memory arr = new ListingManager.StrikeDetails[](5);

    arr[0] = ListingManager.StrikeDetails({strikePrice: 1300 ether, skew: 1});
    arr[1] = ListingManager.StrikeDetails({strikePrice: 1000 ether, skew: 2});
    arr[2] = ListingManager.StrikeDetails({strikePrice: 1300 ether, skew: 3});
    arr[3] = ListingManager.StrikeDetails({strikePrice: 1000 ether + 1, skew: 4});
    arr[4] = ListingManager.StrikeDetails({strikePrice: 1500 ether, skew: 5});

    // strikes are sorted by strikePrice, skews are ignored (but should move along with the strikePrice)
    ListingManager.StrikeDetails[] memory res = listingManager.TEST_quickSortStrikes(arr);

    assertEq(res[0].strikePrice, 1000 ether);
    assertEq(res[0].skew, 2);

    assertEq(res[1].strikePrice, 1000 ether + 1);
    assertEq(res[1].skew, 4);

    assertEq(res[2].strikePrice, 1300 ether);
    assertEq(res[2].skew, 3);

    assertEq(res[3].strikePrice, 1300 ether);
    assertEq(res[3].skew, 1);

    assertEq(res[4].strikePrice, 1500 ether);
    assertEq(res[4].skew, 5);
  }

  function testQuickSortStrikesEmptyArray() public {
    // Note, this is because end of -1 is passed in (as it is an int). In other usage this could be an arithmetic
    // underflow if you do length - 1 (if length is 0)

    // ListingManager.StrikeDetails[] memory arr = new ListingManager.StrikeDetails[](0);
    // TODO: figure out expectRevert for "Index out of bounds"
    // vm.expectRevert();
    // ListingManager.StrikeDetails[] memory res = listingManager.TEST_quickSortStrikes(arr);
  }

  function testQuickSortStrikesOneItem() public {
    ListingManager.StrikeDetails[] memory arr = new ListingManager.StrikeDetails[](1);
    arr[0] = ListingManager.StrikeDetails({strikePrice: 1300 ether, skew: 3});

    ListingManager.StrikeDetails[] memory res = listingManager.TEST_quickSortStrikes(arr);
    assertEq(res.length, 1);
    assertEq(res[0].strikePrice, 1300 ether);
    assertEq(res[0].skew, 3);
  }

  function testOnlyOwnerCanSetRiskCouncil() public {
    vm.prank(address(0xcc));
    vm.expectRevert("Ownable: caller is not the owner");
    listingManager.setRiskCouncil(address(0x1));

    listingManager.setRiskCouncil(address(0x2));
    assertEq(listingManager.riskCouncil(), address(0x2));
  }

  function testOnlyOwnerCanSetParams(
    uint newBoardMinExpiry,
    uint newStrikeMinExpiry,
    uint numWeeklies,
    uint numMonthlies,
    uint maxNumStrikes,
    uint maxScaledMoneyness
  ) public {
    vm.prank(address(0xcc));
    vm.expectRevert("Ownable: caller is not the owner");
    listingManager.setListingManagerParams(
      newBoardMinExpiry, newStrikeMinExpiry, numWeeklies, numMonthlies, maxNumStrikes, maxScaledMoneyness
    );

    listingManager.setListingManagerParams(
      newBoardMinExpiry, newStrikeMinExpiry, numWeeklies, numMonthlies, maxNumStrikes, maxScaledMoneyness
    );

    assertEq(listingManager.newBoardMinExpiry(), newBoardMinExpiry);
    assertEq(listingManager.newStrikeMinExpiry(), newStrikeMinExpiry);
    assertEq(listingManager.numWeeklies(), numWeeklies);
    assertEq(listingManager.numMonthlies(), numMonthlies);
    assertEq(listingManager.maxNumStrikes(), maxNumStrikes);
    assertEq(listingManager.maxScaledMoneyness(), maxScaledMoneyness);
  }
}
