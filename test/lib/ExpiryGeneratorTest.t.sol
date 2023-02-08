//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "openzeppelin/utils/Arrays.sol";
import "";
import "forge-std/test";

contract ExpiryGeneratorTest is Test {
  using stdJson for string;

  uint[] fridays;

  function setUp() public {
    // load fridays.json into strikePriceTester
    string memory path = string.concat(vm.projectRoot(), "/script/params/fridays.json");
    string memory json = vm.readFile(path);
    fridays = json.readUintArray(".fridays");
  }

}