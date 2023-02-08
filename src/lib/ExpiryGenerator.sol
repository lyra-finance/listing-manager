//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "openzeppelin/utils/Arrays.sol";

/**
 * @title Automated Expiry Generator
 * @author Lyra
 * @notice This Library automatically generates expiry times for various boards
 *         The intent being to automate the way that boards and strikes are listed
 *         Whilst ensuring that the expiries make sense are in reasonable timeframes
 */
library ExpiryGenerator {

  using DecimalMath for uint;
  using SignedDecimalMath for int;
  using FixedPointMathLib for int;
  
  /// @notice Explain to an end user what this does
  /// @dev Explain to a developer any extra details
  /// @param Documents a parameter just like in doxygen (must be followed by parameter name)
  /// @return Documents the return variables of a contract’s function state variable
  /// @inheritdoc	Copies all missing tags from the base function (must be followed by the contract name)
  function getNextExpiries(
    uint[] storage fridays,
    uint[] storage liveExpiries
  ) public view returns(uint) {
    // TODO: gets current latest board and then finds next expiry on the friday
    
    for(liveExpiries)

  }

  function getNewExpiry(
    uint[] storage fridays,
  ) public view returns(uint) {
    // TODO: given no live boards it finds the next friday from the current timestamp, given a buffer,
    //      and then returns that timestamp
    
  }


  function _expiryGenerator(
    uint[] storage fridays
  ) internal view returns (uint[] memory) {

  }


  /////////////
  // Helpers //
  /////////////

  /**  @notice This function finds the first friday relative to the current timestamp
  * @dev Friday's array has to be sorted in ascending order
  * @param timestamp The current timestamp
  * @param friday The sorted storage array of fridays
  * @return uint the timestamp of the closest friday to the current timestamp, 
  */ 
  function _getNearestFriday(uint timestamp, uint[] storage friday) internal pure returns (uint) {
    for (uint i = 0; i < friday.length; i++) {
      if (timestamp > friday[i]) {
        // need to consider the case where this is the 0th friday in the array. 
        return friday[i - 1];
      }
    }

    revert ("No friday found");
  }
}