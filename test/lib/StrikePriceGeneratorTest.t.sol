// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import "src/lib/StrikePriceGenerator.sol";

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

  function getStep(uint nearestPivot, uint tTarget) public pure returns (uint) {
    return StrikePriceGenerator.getStep(nearestPivot, tTarget);
  }

  function getATMStrike(uint spot, uint nearestPivot, uint step) public pure returns (uint) {
    return StrikePriceGenerator.getATMStrike(spot, nearestPivot, step);
  }

  function getStrikeRange(uint tTarget, uint spot, uint maxScaledMoneyness) public pure returns (uint, uint) {
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

    uint[] memory newStrikes = tester.getNewStrikes(_secToAnnualized(2 weeks), 1000e18, 120e16, 3, liveStrikes);

    assertEq(newStrikes.length, 0);
  }

  function testDoesNotAddATMAndAssymetricAdd() public {
    // 3 day expiry setup
    uint tTarget = _secToAnnualized(3 days);
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
    uint tTarget = _secToAnnualized(3 days);
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

  function testStrikeRanges() public {
    // ETH price range regular
    (uint min, uint max) = tester.getStrikeRange(_secToAnnualized(1 days), 1_499.1 * 1e18, 1.2e18);

    assertApproxEqAbs(min, 1407.83639933e18, 1e10);
    assertApproxEqAbs(max, 1596.27980287e18, 1e10);

    // BTC price range regular
    (min, max) = tester.getStrikeRange(_secToAnnualized(7 days), 18123.69 * 1e18, 0.7e18);

    assertApproxEqAbs(min, 16449.259404685611e18, 1e10);
    assertApproxEqAbs(max, 19968.567042145074e18, 1e10);

    // Shitcoins price range regular
    (min, max) = tester.getStrikeRange(_secToAnnualized(91 days), 1.23 * 1e18, 2.2e18);

    assertApproxEqAbs(min, 0.41004927327064006e18, 1e10);
    assertApproxEqAbs(max, 3.6895565938522177e18, 1e10);

    // Small DTE -> checks if converges to spot
    (min, max) = tester.getStrikeRange(_secToAnnualized(86 seconds), 723.01 * 1e18, 1.21e18);

    assertApproxEqAbs(min, 721.56674931315e18, 1e10);
    assertApproxEqAbs(max, 724.4561374226e18, 1e10);

    // Huge DTE and spot (2.33 years, 100mm spot) -> checks for overflow
    (min, max) = tester.getStrikeRange(2.33 * 1e18, 100_000_000 * 1e18, 3.2e18);

    assertApproxEqAbs(min, 756223.8708292978e18, 1e10);
    assertApproxEqAbs(max, 13223597383.977974e18, 1e14); // to the nearest 100th of a cent

    // 1 Sec DTE, ultra small spot -> checks for underflow / rounding errors
    (min, max) = tester.getStrikeRange(1, 0.0000001 * 1e18, 0.1e18);

    assertApproxEqAbs(min, 99998219291, 1e7); // 5th digit accuracy
    assertApproxEqAbs(max, 100001780740, 1e7);
  }

  //////////////
  // Get Step //
  //////////////

  function testBlocksTinyPivots() public {
    vm.expectRevert(abi.encodeWithSelector(StrikePriceGenerator.PivotLessThanOrEqualToStepDiv.selector, 40, 40));

    tester.getStep(40, _secToAnnualized(1 days));
  }

  function testGetsCorrectTimeHorizon() public {
    assertEq(tester.getStep(1000e18, _secToAnnualized(3 days)), 25e18);

    assertEq(tester.getStep(1000e18, _secToAnnualized(3 weeks)), 50e18);

    assertEq(tester.getStep(1000e18, _secToAnnualized(6 weeks)), 100e18);

    assertEq(tester.getStep(1000e18, _secToAnnualized(104 weeks)), 200e18);
  }

  function testGetsCorrectAbsStep() public {
    assertEq(tester.getStep(5000e18, _secToAnnualized(6 weeks)), 500e18);

    assertEq(tester.getStep(13_456_000e18, _secToAnnualized(5 days)), 336_400e18);

    assertEq(tester.getStep(1e18, _secToAnnualized(100 weeks)), 2e17);
  }

  /////////////
  // Helpers //
  /////////////

  function _secToAnnualized(uint sec) public pure returns (uint) {
    return (sec * 1e18) / uint(365 days);
  }
}
