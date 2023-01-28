// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import "../src/lib/StrikePriceGenerator.sol";

contract StrikePriceTester {
  // todo [Josh]: can probably hardcode
  uint[] pivots;

  constructor(uint[] memory _pivots) {
    for (uint i; i < _pivots.length; i++) {
      pivots.push(_pivots[i] * 1e18);
    }
  }

  function getNewStrikes(
    uint tTarget,
    uint spot,
    uint maxScaledMoneyness,
    uint maxNumStrikes,
    uint[] memory liveStrikes
  ) public view returns (uint[] memory newStrikes) {
    return StrikePriceGenerator.getNewStrikes(tTarget, spot, maxScaledMoneyness, maxNumStrikes, liveStrikes, pivots);
  }

  function getLeftNearestPivot(uint spot) public view returns (uint) {
    return StrikePriceGenerator.getLeftNearestPivot(pivots, spot);
  }

  function getStep(uint nearestPivot, uint tTarget) public view returns (uint) {
    return StrikePriceGenerator.getStep(nearestPivot, tTarget);
  }

  function getATMStrike(uint spot, uint nearestPivot, uint step) public view returns (uint) {
    return StrikePriceGenerator.getATMStrike(spot, nearestPivot, step);
  }

  function getStrikeRange(uint tTarget, uint spot, uint maxScaledMoneyness) public view returns (uint, uint) {
    return StrikePriceGenerator.getStrikeRange(tTarget, spot, maxScaledMoneyness);
  }
}

contract StrikePriceGeneratorTest is Test {
  using stdJson for string;

  uint[] pivots;

  StrikePriceTester tester;

  function setUp() public {
    // load pivots.json into strikePriceTester
    string memory path = string.concat(vm.projectRoot(), "/script/params/pivots.json");
    string memory json = vm.readFile(path);
    pivots = json.readUintArray(".pivots");
    tester = new StrikePriceTester(pivots);
  }

  /////////////////////
  // Get New Strikes //
  /////////////////////

  function testAddsZeroStrikes() public {
    // 20 existing strikes
    uint[] memory liveStrikes = new uint[](3);
    liveStrikes[0] = 1000e18;
    liveStrikes[1] = 1025e18;
    liveStrikes[2] = 1050e18;

    uint[] memory newStrikes =
      tester.getNewStrikes(uint(2 weeks) * 1e18 / uint(365 days), 1000e18, 120e16, 3, liveStrikes);

    assertEq(newStrikes.length, 0);
  }

  function testDoesNotAddATMAndAssymetricAdd() public {
    // 3 day expiry setup
    uint tTarget = uint(3 days) * 1e18 / uint(365 days);
    uint moneyness = 120e16;
    uint maxStrikes = 8;

    // 20 existing strikes
    uint[] memory liveStrikes = new uint[](3);
    liveStrikes[0] = 1000e18;
    liveStrikes[1] = 1025e18;
    liveStrikes[2] = 1050e18;
    uint spot = 1000e18;

    uint[] memory newStrikes = tester.getNewStrikes(tTarget, spot, moneyness, maxStrikes, liveStrikes);

    assertEq(newStrikes[0], 975e18);
    assertEq(newStrikes[1], 950e18);
    assertEq(newStrikes[2], 925e18);
    assertEq(newStrikes[3], 1075e18);
    assertEq(newStrikes[4], 900e18);
  }

  function testAddsNewStrikesAndATM() public {
    // 2 week expiry setup
    uint tTarget = uint(3 days) * 1e18 / uint(365 days);
    uint moneyness = 120e16;
    uint maxStrikes = 10;

    // 20 existing strikes
    uint[] memory liveStrikes = new uint[](5);
    liveStrikes[0] = 1000e18;
    liveStrikes[1] = 1025e18;
    liveStrikes[2] = 1050e18;
    liveStrikes[3] = 1075e18;
    liveStrikes[4] = 1100e18;
    uint spot = 1500e18;

    uint[] memory newStrikes = tester.getNewStrikes(tTarget, spot, moneyness, maxStrikes, liveStrikes);

    assertEq(newStrikes[0], 1500e18);
    assertEq(newStrikes[1], 1475e18);
    assertEq(newStrikes[2], 1525e18);
    assertEq(newStrikes[3], 1450e18);
    assertEq(newStrikes[4], 1550e18);
  }

  //////////////////////
  // Get Left Nearest //
  //////////////////////

  function testSpotAboveMaxPivot() public {
    vm.expectRevert(
      abi.encodeWithSelector(StrikePriceGenerator.SpotPriceAboveMaxStrike.selector, pivots[pivots.length - 1] * 1e18)
    );
    tester.getLeftNearestPivot(2_000_000_000_000e18);
  }

  function testSpotIsZero() public {
    vm.expectRevert(StrikePriceGenerator.SpotPriceIsZero.selector);
    tester.getLeftNearestPivot(0);
  }

  function testChoosesLeftNearest() public {
    // takes left nearest even if closer to the right pivot
    assertEq(tester.getLeftNearestPivot(1_934_568e18), 1_000_000e18);

    // chooses pivot if exactly on pivot
    assertEq(tester.getLeftNearestPivot(5000e18), 5000e18);

    // couple random examples
    assertEq(tester.getLeftNearestPivot(165e16), 1e18);

    assertEq(tester.getLeftNearestPivot(1550e18), 1000e18);
  }

  ////////////////////
  // Get ATM Strike //
  ////////////////////

  function testGetsNearestStrikeForATM() public {
    // unlike getLeftNearestPivot, gets nearest strike
    assertEq(tester.getATMStrike(1357e18, 1000e18, 100e18), 1400e18);

    assertEq(tester.getATMStrike(1_456_357e18, 1_000_000e18, 50e18), 1_456_350e18);
  }

  function testGetsPivotIfCloseset() public {
    assertEq(tester.getATMStrike(10_057e18, 10_000e18, 200e18), 10_000e18);

    assertEq(tester.getATMStrike(1_856e15, 1e18, 500e15), 2e18);
  }

  //////////////////////
  // Get Strike Range //
  //////////////////////

  //////////////
  // Get Step //
  //////////////

  function testBlocksTinyPivots() public {
    vm.expectRevert(abi.encodeWithSelector(StrikePriceGenerator.PivotLessThanOrEqualToStepDiv.selector, 40, 40));

    tester.getStep(40, uint(1 days) * 1e18 / uint(365 days));
  }

  function testGetsCorrectTimeHorizon() public {
    assertEq(tester.getStep(1000e18, uint(3 days) * 1e18 / uint(365 days)), 25e18);

    assertEq(tester.getStep(1000e18, uint(3 weeks) * 1e18 / uint(365 days)), 50e18);

    assertEq(tester.getStep(1000e18, uint(6 weeks) * 1e18 / uint(365 days)), 100e18);

    assertEq(tester.getStep(1000e18, uint(104 weeks) * 1e18 / uint(365 days)), 200e18);
  }

  function testGetsCorrectAbsStep() public {
    assertEq(tester.getStep(5000e18, uint(6 weeks) * 1e18 / uint(365 days)), 500e18);

    assertEq(tester.getStep(13_456_000e18, uint(5 days) * 1e18 / uint(365 days)), 336_400e18);

    assertEq(tester.getStep(1e18, uint(100 weeks) * 1e18 / uint(365 days)), 2e17);
  }

  /////////////
  // Helpers //
  /////////////

  // function _convertTo18(uint[] memory inputs) internal pure {
  //   for (uint i; i < inputs.length; i++) {
  //     inputs[i] = inputs[i] * DecimalMath.UNIT;
  //   }
  // }
}
