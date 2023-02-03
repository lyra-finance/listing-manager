// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/lib/VolGenerator.sol";
import "test/mocks/VolGeneratorTester.sol";
contract VolGeneratorTest is Test {
  VolGeneratorTester tester;
  uint defaultATMSkew = 1e18;

  function setUp() public {
    tester = new VolGeneratorTester();
  }

  function testStrikeInterpolation() public {
    // initial setup
    uint spot = 1496.2e18;
    uint[] memory strikes = new uint[](5);
    strikes[0] = 1400e18;
    strikes[1] = 1450e18;
    strikes[2] = 1500e18;
    strikes[3] = 1550e18;
    strikes[4] = 1650e18;

    uint[] memory skews = new uint[](5);
    skews[0] = 1.1e18;
    skews[1] = 1.2e18;
    skews[2] = 1.02e18;
    skews[3] = 0.96e18;
    skews[4] = 1.33e18;

    VolGenerator.Board memory liveBoard = VolGenerator.Board({
      tAnnualized: _secToAnnualized(7 days),
      baseIv: 0.567e18,
      orderedStrikePrices: strikes,
      orderedSkews: skews
    });

    // Strike: $1425
    uint newSkew = tester.getSkewForLiveBoard(1425e18, liveBoard);
    assertApproxEqAbs(newSkew, 1.1515245649507764e18, 1e10);
  }

  /////////////
  // Helpers //
  /////////////

  function _secToAnnualized(uint sec) public pure returns (uint) {
    return (sec * 1e18) / uint(365 days);
  }

}
