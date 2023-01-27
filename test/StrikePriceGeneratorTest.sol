// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";  
import "forge-std/StdJson.sol";

import "../src/lib/StrikePriceGenerator.sol";

contract StrikePriceTester {
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
    return StrikePriceGenerator.getNewStrikes(
      tTarget, 
      spot,
      maxScaledMoneyness,
      maxNumStrikes,
      liveStrikes,
      pivots
    );
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


  //////////////////////
  // Get Left Nearest //
  //////////////////////

  function testSpotAboveMaxPivot() public {
    vm.expectRevert(abi.encodeWithSelector(
      StrikePriceGenerator.SpotPriceAboveMaxStrike.selector,
      pivots[pivots.length - 1] * 1e18
    ));
    tester.getLeftNearestPivot(2_000_000_000_000e18);
  }

  function testSpotIsZero() public {
    vm.expectRevert(
      StrikePriceGenerator.SpotPriceIsZero.selector
    );
    tester.getLeftNearestPivot(0);
  }

  function testChoosesLeftNearest() public {
    // takes left nearest even if closer to the right pivot
    assertEq(
      tester.getLeftNearestPivot(1_934_568e18),
      1_000_000e18
    );

    // chooses pivot if exactly on pivot
    assertEq(
      tester.getLeftNearestPivot(5000e18),
      5000e18
    );

    // couple random examples
    assertEq(
      tester.getLeftNearestPivot(165e16),
      1e18
    );

    assertEq(
      tester.getLeftNearestPivot(1550e18),
      1000e18
    );
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
