// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";  
import "forge-std/StdJson.sol";

import "../src/lib/StrikePriceGenerator.sol";

contract StrikePriceTester {
  uint[] pivots;
  constructor(uint[] memory _pivots) {
    pivots = _pivots;
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
}

contract StrikePriceGeneratorTest is Test {
  using stdJson for string;

  StrikePriceTester tester;
  function setUp() public {
    // load pivots.json into strikePriceTester
    string memory path = string.concat(vm.projectRoot(), "/script/params/pivots.json");
    string memory json = vm.readFile(path);
    console2.log(json);
    // uint[] memory pivots = json.readUintArray(".pivots[]");
    uint[] memory pivots = abi.decode(stdJson.parseRaw(json, ".pivots"), (uint256[]));
    tester = new StrikePriceTester(pivots);
  }

  /////////////////////
  // Get New Strikes //
  /////////////////////

  function test() public {

  }

}
