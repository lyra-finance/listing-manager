// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/lib/VolGenerator.sol";
import "test/mocks/VolGeneratorTester.sol";
contract VolGeneratorAcrossBoardTest is Test {
  VolGeneratorTester tester;
  uint defaultATMSkew = 1e18;
  uint defaultSpot = 1496.2e18;

  function setUp() public {
    tester = new VolGeneratorTester();
  }

  function testInterpolationCloseToLeftPoint() public {
    VolGenerator.Board memory shortDatedBoard = getLiveBoardA();
    VolGenerator.Board memory longDatedBoard = getLiveBoardB();
    uint tTarget = _secToAnnualized(12 days);

    // get Base IV first: 
    uint atmVol = tester.getSkewForNewBoard(defaultSpot, tTarget, 1e18, shortDatedBoard, longDatedBoard);
    uint baseIv = atmVol * 1e18 / defaultATMSkew;
    // todo: double check that ok to be off by 1e16
    assertApproxEqAbs(baseIv, 0.5965411413724958e18, 1e10); 

    // strike $1400
    uint newSkew = tester.getSkewForNewBoard(1400e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 1.1556934548479152e18, 1e10);

    // strike $1450
    newSkew = tester.getSkewForNewBoard(1450e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 1.1278576322505167e18, 1e10);

    // strike $1500
    newSkew = tester.getSkewForNewBoard(1500e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 1e18, 1e10);

    // strike $1550
    newSkew = tester.getSkewForNewBoard(1550e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 0.8741978629034658e18, 1e10);

    // strike $1600
    newSkew = tester.getSkewForNewBoard(1600e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 0.8545273360149661e18, 1e10);
  }

  /////////////
  // Helpers //
  /////////////

  function _secToAnnualized(uint sec) public pure returns (uint) {
    return (sec * 1e18) / uint(365 days);
  }

  function getLiveBoardA() internal pure returns (VolGenerator.Board memory) {
    // Live Board A setup
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

    return VolGenerator.Board({
      tAnnualized: _secToAnnualized(7 days),
      baseIv: 0.567e18,
      orderedStrikePrices: strikes,
      orderedSkews: skews
    });
  }

  function getLiveBoardB() internal pure returns (VolGenerator.Board memory) {
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

    return VolGenerator.Board({
      tAnnualized: _secToAnnualized(21 days),
      baseIv: 0.66e18,
      orderedStrikePrices: strikes,
      orderedSkews: skews
    });

  }

}
