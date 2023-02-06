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
  function testExtrapolateloseToExisting() public {
    // Chose 21 day expiry as it's on the edge closest to 22 days
    // note: in integration contracts, this would be done algorithmically
    VolGenerator.Board memory edgeBoard = getLiveBoardB();
    uint tTarget = _secToAnnualized(22 days);

    // get Base IV first:
    uint atmVol = tester.getSkewForNewBoard(defaultSpot, tTarget, 1e18, defaultSpot, edgeBoard);
    uint baseIv = atmVol * 1e18 / defaultATMSkew;
    assertApproxEqAbs(baseIv, 0.6119762171997786e18, 1e10);


    // strike $1310
    uint newSkew = tester.getSkewForNewBoard(1310e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.3917726712992229e18, 1e10);

    // strike $1455.05
    newSkew = tester.getSkewForNewBoard(1455.05e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.0802852625137416e18, 1e10);

    // strike $1511.1
    newSkew = tester.getSkewForNewBoard(1511.1e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 0.9601148482618476e18, 1e10);

    // strike $1600
    newSkew = tester.getSkewForNewBoard(1600e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 0.6574465763453895e18, 1e10);

    // strike $1774
    newSkew = tester.getSkewForNewBoard(1774e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.2941679394404522e18, 1e10);
  }

  function testExtrapolateLargeExpiryFarFromExisting_TODO() public {
    // Chose 21 day expiry as it's on the edge closest to 90 days
    // note: in integration contracts, this would be done algorithmically
    VolGenerator.Board memory edgeBoard = getLiveBoardB();
    uint tTarget = _secToAnnualized(90 days);

    // get Base IV first:
    uint atmVol = tester.getSkewForNewBoard(defaultSpot, tTarget, 1e18, defaultSpot, edgeBoard);
    uint baseIv = atmVol * 1e18 / defaultATMSkew;
    assertApproxEqAbs(baseIv, 0.6119762171997786e18, 1e10);

    // strike $1200
    uint newSkew = tester.getSkewForNewBoard(1200e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.3200323862509369e18, 1e10);

    // strike $1300
    newSkew = tester.getSkewForNewBoard(1300e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.1913905575286992e18, 1e10);

    // strike $1400
    newSkew = tester.getSkewForNewBoard(1400e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.093970716415067e18, 1e10);

    // strike $1500
    newSkew = tester.getSkewForNewBoard(1500e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 0.9962376637400737e18, 1e10);

    // strike $1600
    newSkew = tester.getSkewForNewBoard(1600e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 0.8501003936076388e18, 1e10);

    // strike $1700
    newSkew = tester.getSkewForNewBoard(1700e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 0.6826183268980716e18, 1e10);

    // strike $1800
    newSkew = tester.getSkewForNewBoard(1800e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 0.937612674242019e18, 1e10);
  }

  function testExtrapolateSmallExpiryFarFromExisting_TODO() public {
     // Chose 7 day expiry as it's on the edge closest to 7 days
    // note: in integration contracts, this would be done algorithmically
    VolGenerator.Board memory edgeBoard = getLiveBoardA();
    uint tTarget = _secToAnnualized(1 days);

    // get Base IV first:
    uint atmVol = tester.getSkewForNewBoard(defaultSpot, tTarget, 1e18, defaultSpot, edgeBoard);
    uint baseIv = atmVol * 1e18 / defaultATMSkew;
    assertApproxEqAbs(baseIv, 0.5865911557680897e18, 1e10);

    // strike $1200
    uint newSkew = tester.getSkewForNewBoard(1200e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.063261854303479e18, 1e10);

    // strike $1300
    newSkew = tester.getSkewForNewBoard(1300e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.063261854303479e18, 1e10);

    // strike $1400
    newSkew = tester.getSkewForNewBoard(1400e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.063261854303479e18, 1e10);

    // strike $1500
    newSkew = tester.getSkewForNewBoard(1500e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 0.9775797353092716e18, 1e10);

    // strike $1600
    newSkew = tester.getSkewForNewBoard(1600e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.2855802420214792e18, 1e10);

    // strike $1700
    newSkew = tester.getSkewForNewBoard(1700e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.2855802420214792e18, 1e10);

    // strike $1800
    newSkew = tester.getSkewForNewBoard(1800e18, tTarget, baseIv, defaultSpot, edgeBoard);
    assertApproxEqAbs(newSkew, 1.2855802420214792e18, 1e10);
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
