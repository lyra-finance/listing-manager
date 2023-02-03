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

  function testInterpolation() public {
    // initial setup
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

    // Strike: $1450
    newSkew = tester.getSkewForLiveBoard(1450e18, liveBoard);
    assertApproxEqAbs(newSkew, 1.2e18, 1e10);

    // Strike: $1569
    // todo [Vlad/Josh] -> seems to be slightly off
    newSkew = tester.getSkewForLiveBoard(1569e18, liveBoard);
    assertApproxEqAbs(newSkew, 1.0350546610797016e18, 1e10);
  }

  function testInterpolationNearExistingStrikes() public {
    // initial setup
    uint[] memory strikes = new uint[](5);
    strikes[0] = 1300e18;
    strikes[1] = 1400e18;
    strikes[2] = 1500e18;
    strikes[3] = 1600e18;
    strikes[4] = 1700e18;

    uint[] memory skews = new uint[](5);
    skews[0] = 1.32e18;
    skews[1] = 1.1e18;
    skews[2] = 0.92e18;
    skews[3] = 0.6e18;
    skews[4] = 1.2e18;

    VolGenerator.Board memory liveBoard = VolGenerator.Board({
      tAnnualized: _secToAnnualized(21 days),
      baseIv: 0.66e18,
      orderedStrikePrices: strikes,
      orderedSkews: skews
    });

    // Strike: $1300.00001
    uint newSkew = tester.getSkewForLiveBoard(1300.00001e18, liveBoard);
    assertApproxEqAbs(newSkew, 1.3199999790672716e18, 1e10);

    // Strike: $1599.99
    newSkew = tester.getSkewForLiveBoard(1599.99e18, liveBoard);
    assertApproxEqAbs(newSkew, 0.6000392518815546e18, 1e10);
  }

  function testExtrapolationNearStrike() public {
    // initial setup
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

    // strike $1399
    uint newSkew = tester.getSkewForLiveBoard(1399e18, liveBoard);
    assertApproxEqAbs(newSkew, 1.1e18, 1e10);

    // strike $900
    newSkew = tester.getSkewForLiveBoard(900e18, liveBoard);
    assertApproxEqAbs(newSkew, 1.1e18, 1e10);

    // strike $1700
    newSkew = tester.getSkewForLiveBoard(1700e18, liveBoard);
    assertApproxEqAbs(newSkew, 1.33e18, 1e10);

  }

  /////////////
  // Helpers //
  /////////////

  function _secToAnnualized(uint sec) public pure returns (uint) {
    return (sec * 1e18) / uint(365 days);
  }

}
