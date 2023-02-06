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

  function testInterpolationCloseToShortDatedBoard() public {
    VolGenerator.Board memory shortDatedBoard = getLiveBoardA();
    VolGenerator.Board memory longDatedBoard = getLiveBoardB();
    uint tTarget = _secToAnnualized(12 days);

    // get Base IV first:
    uint atmVol = tester.getSkewForNewBoard(defaultSpot, tTarget, 1e18, shortDatedBoard, longDatedBoard);
    uint baseIv = atmVol * 1e18 / defaultATMSkew;
    assertApproxEqAbs(baseIv, 0.6025821525077288e18, 1e10);

    // strike $1400
    uint newSkew = tester.getSkewForNewBoard(1400e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 1.1441073881172668e18, 1e10);

    // strike $1450
    newSkew = tester.getSkewForNewBoard(1450e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 1.1165506254182895e18, 1e10);

    // strike $1500
    newSkew = tester.getSkewForNewBoard(1500e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 0.9899747924659027e18, 1e10);

    // strike $1550
    newSkew = tester.getSkewForNewBoard(1550e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 0.8654338479019942e18, 1e10);

    // strike $1600
    newSkew = tester.getSkewForNewBoard(1600e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 0.8459605221278568e18, 1e10);
  }

  function testInterpolationCloseToLongDatedBoard() public {
    VolGenerator.Board memory shortDatedBoard = getLiveBoardA();
    VolGenerator.Board memory longDatedBoard = getLiveBoardB();
    uint tTarget = _secToAnnualized(20 days);

    // get Base IV first:
    uint atmVol = tester.getSkewForNewBoard(defaultSpot, tTarget, 1e18, shortDatedBoard, longDatedBoard);
    uint baseIv = atmVol * 1e18 / defaultATMSkew;
    assertApproxEqAbs(baseIv, 0.611354437097115e18, 1e10);

    // strike $1375
    uint newSkew = tester.getSkewForNewBoard(1375e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 1.2442187252774846e18, 1e10);

    // strike $1425
    newSkew = tester.getSkewForNewBoard(1425e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 1.1390715198328825e18, 1e10);

    // strike $1531.02
    newSkew = tester.getSkewForNewBoard(1531.02e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 0.8983410630080852e18, 1e10);

    // strike $1610
    newSkew = tester.getSkewForNewBoard(1610e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 0.7522849269479505e18, 1e10);

    // strike $1700
    newSkew = tester.getSkewForNewBoard(1700e18, tTarget, baseIv, shortDatedBoard, longDatedBoard);
    assertApproxEqAbs(newSkew, 1.2939709280359952e18, 1e10);
  }

  // todo: finish
  function testExtrapolateloseToExisting_TODO() public {
    // strikes: [1310, 1455.05, 1511.10, 1600, 1774],

    // Chose 21 day expiry as it's on the edge closest to 22 days
    // note: in integration contracts, this would be done algorithmically
    VolGenerator.Board memory edgeBoard = getLiveBoardB();
    uint tTarget = _secToAnnualized(22 days);

    // get Base IV first:
    uint atmVol = tester.getSkewForNewBoard(defaultSpot, tTarget, 1e18, defaultSpot, edgeBoard);
    uint baseIv = atmVol * 1e18 / defaultATMSkew;
    assertApproxEqAbs(baseIv, 0.6119762171997786e18, 1e10);


    // // result:
    // "baseIv":0.5875674529166249
    // "strikePrice":1310,"skew":1.4495897796173352
    // "strikePrice":1455.05,"skew":1.1251625411995716
    // "strikePrice":1511.1,"skew":1
    // "strikePrice":1600,"skew":0.6847582635927397
    // "strikePrice":1774,"skew":1.3479303458157745
  }

  function testExtrapolateLargeExpiryFarFromExisting_TODO() public {
    // tAnnualized: 90/365,
    // strikes: [1200, 1300, 1400, 1500, 1600, 1700, 1800]

    // // result:
    // "baseIv":0.6096737568875953
    // "strikePrice":1200,"skew":1.325017547816124
    // "strikePrice":1300,"skew":1.1958898974527652
    // "strikePrice":1400,"skew":1.098102145935824
    // "strikePrice":1500,"skew":1
    // "strikePrice":1600,"skew":0.853310835906558
    // "strikePrice":1700,"skew":0.6851962656535058
    // "strikePrice":1800,"skew":0.9411536105973298
  }

  function testExtrapolateSmallExpiryFarFromExisting_TODO() public {
    // tAnnualized: 1/365,
    // strikes: [1200, 1300, 1400, 1500, 1600, 1700, 1800]

    // // result:
    // "baseIv":0.5734396267905288
    // "strikePrice":1200,"skew":1.0876471922437108
    // "strikePrice":1300,"skew":1.0876471922437108
    // "strikePrice":1400,"skew":1.0876471922437108
    // "strikePrice":1500,"skew":1
    // "strikePrice":1600,"skew":1.315064332440123
    // "strikePrice":1700,"skew":1.315064332440123
    // "strikePrice":1800,"skew":1.315064332440123
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
    skews[3] = 0.95e18;
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
