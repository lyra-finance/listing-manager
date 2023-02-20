//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "../../lib/openzeppelin-contracts/contracts/utils/Arrays.sol";
import "src/lib/ExpiryGenerator.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "../../src/ListingManagerLibrarySettings.sol";

contract ExpiryGeneratorTest is Test, ListingManagerLibrarySettings {
  using stdJson for string;

  uint[] liveExpiries;

  function setUp() public {
    // 1/03/2023 00:00:00
    vm.warp(1677628800);
  }

  function testGetExpiriesBase() public {
    uint nWeeks = 1;
    uint nMonths = 2;
    uint[] memory expiriesReturned = ExpiryGenerator.getExpiries(nWeeks, nMonths, block.timestamp, LAST_FRIDAYS);
    for (uint i; i < expiriesReturned.length; i++) {
      console.log(expiriesReturned[i]);
    }

    assertEq(expiriesReturned.length, nWeeks + nMonths);
    // check expiries[0], first weekly is correct, 3/3/2023 is the first expiry
    assertEq(expiriesReturned[0], ExpiryGenerator.getNextFriday(block.timestamp));
    // check expiries[1], first monthly is correct, 3/31/2023 is the second expiry
    assertEq(expiriesReturned[1], 1680249600);
    // check Expiuries[2], second monthly is correct, last friday in april is the third expiry
    assertEq(expiriesReturned[2], 1682668800);
  }

  function testGet3MonthsWorthOfWeeklies() public {
    uint nWeeks = 12;
    uint nMonths = 0;
    uint[] memory expiriesReturned = ExpiryGenerator.getExpiries(nWeeks, nMonths, block.timestamp, LAST_FRIDAYS);

    uint startTime = ExpiryGenerator.getNextFriday(block.timestamp);

    for (uint i; i < expiriesReturned.length; i++) {
      assertEq(expiriesReturned[i], startTime + (i * 7 days));
    }
  }

  function testGet6MonthsOfMonthlies() public {
    uint nWeeks = 0;
    uint nMonths = 6;
    uint[] memory expiriesReturned = ExpiryGenerator.getExpiries(nWeeks, nMonths, block.timestamp, LAST_FRIDAYS);

    uint monthlyIndex = 0;
    for (uint i; i < LAST_FRIDAYS.length; i++) {
      if (LAST_FRIDAYS[i] > block.timestamp) {
        monthlyIndex = i;
        break;
      }
    }

    for (uint i; i < expiriesReturned.length; i++) {
      assertEq(expiriesReturned[i], LAST_FRIDAYS[monthlyIndex + i]);
    }
  }

  function testGet3Monthlies5Weeklies() public {
    uint nWeeks = 5;
    uint nMonths = 3;
    uint[] memory expiriesReturned = ExpiryGenerator.getExpiries(nWeeks, nMonths, block.timestamp, LAST_FRIDAYS);

    uint monthlyIndex = 0;
    for (uint i; i < LAST_FRIDAYS.length; i++) {
      if (LAST_FRIDAYS[i] > block.timestamp) {
        monthlyIndex = i;
        break;
      }
    }

    uint startTime = ExpiryGenerator.getNextFriday(block.timestamp);

    for (uint i; i < nWeeks; i++) {
      // should contain every friday 5 weeks out and 2 monthlies out
      assertEq(contains(expiriesReturned, startTime + 7 days), true);
    }

    for (uint i; i < nMonths; i++) {
      // should contain every friday 5 weeks out and 2 monthlies out
      assertEq(contains(expiriesReturned, LAST_FRIDAYS[monthlyIndex + i]), true);
    }

    // print expiriesReturned
    for (uint i; i < expiriesReturned.length; i++) {
      console.log(expiriesReturned[i]);
    }
  }
  //
  //  function testGetNewExpiriesWith1Board() public {
  //    uint nWeeks = 2;
  //    uint nMonths = 3;
  //    liveExpiries.push(1680249600);
  //    liveExpiries.push(1682668800);
  //    uint[] memory expiriesReturned =
  //      ExpiryGenerator.getNextExpiries(nWeeks, nMonths, block.timestamp, LAST_FRIDAYS, liveExpiries);
  //
  //    for (uint i; i < liveExpiries.length; i++) {
  //      assertEq(contains(expiriesReturned, liveExpiries[i]), false);
  //    }
  //
  //    for (uint i; i < expiriesReturned.length; i++) {
  //      console.log(expiriesReturned[i]);
  //    }
  //  }
  //
  //  function testGetNewExpiriesBetweenThreeMonthlies() public {
  //    uint nWeeks = 12;
  //    uint nMonths = 0;
  //    liveExpiries.push(1680249600); // 5 fridays between march - april
  //    liveExpiries.push(1682668800);
  //    liveExpiries.push(1685254400);
  //    uint[] memory expiriesReturned =
  //      ExpiryGenerator.getNextExpiries(nWeeks, nMonths, block.timestamp, LAST_FRIDAYS, liveExpiries);
  //
  //    for (uint i; i < liveExpiries.length; i++) {
  //      assertEq(contains(expiriesReturned, liveExpiries[i]), false);
  //    }
  //
  //    assertEq(contains(expiriesReturned, 1680249600 + 7 days), true);
  //    assertEq(contains(expiriesReturned, 1680249600 + 14 days), true);
  //    assertEq(contains(expiriesReturned, 1680249600 + 21 days), true);
  //    assertEq(contains(expiriesReturned, 1680249600 + 28 days), false); // as already included in the stirkes
  //    assertEq(contains(expiriesReturned, 1682668800 + 7 days), true);
  //    assertEq(contains(expiriesReturned, 1682668800 + 14 days), true);
  //    assertEq(contains(expiriesReturned, 1682668800 + 21 days), true);
  //    assertEq(contains(expiriesReturned, 1682668800 + 28 days), false);
  //
  //    for (uint i; i < expiriesReturned.length; i++) {
  //      console.log(expiriesReturned[i]);
  //    }
  //  }

  function testGetNextFriday() public {
    assertEq(ExpiryGenerator.getNextFriday(1676607004), 1676620800);
    assertEq(ExpiryGenerator.getNextFriday(1676620799), 1676620800);
    assertEq(ExpiryGenerator.getNextFriday(1676620800), 1677225600);
    assertEq(ExpiryGenerator.getNextFriday(1676620801), 1677225600);
  }

  // checks if unordered array contains the timestamp
  function contains(uint[] memory array, uint timestamp) public pure returns (bool) {
    for (uint i; i < array.length; i++) {
      if (array[i] == timestamp) {
        return true;
      }
    }
    return false;
  }
}
