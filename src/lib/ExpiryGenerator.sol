//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "openzeppelin/utils/Arrays.sol";
import "newport/synthetix/SignedDecimalMath.sol";
import "newport/synthetix/DecimalMath.sol";
import "lyra-utils/arrays/UnorderedMemoryArray.sol";
import "newport/libraries/FixedPointMathLib.sol";

import "forge-std/console2.sol";

/**
 * @title Automated Expiry Generator
 * @author Lyra
 * @notice This Library automatically generates expiry times for various boards
 *         The intent being to automate the way that boards and strikes are listed
 *         Whilst ensuring that the expiries make sense are in reasonable timeframes
 */
library ExpiryGenerator {

  using DecimalMath for uint;

  /** @notice Gets the next expiry given the list of live boards
  * @dev generates the next expiry from the largest timestamp passed in by the board
  * @param lastFridays The list of the last fridays of every month.
  * @param liveExpiries The list of the live expiries that correlate to the boards
  * @param nWeeklies The number of weeklies to generate
  * @param nMonthlies The number of monthlies to generate
  * @param timestamp The current timestamp
  * @return expiries The expiries generated that fulfil the given parameters
  */
  function getNextExpiries(
    uint nWeeklies,
    uint nMonthlies,
    uint timestamp,
    uint[] storage lastFridays,
    uint[] storage liveExpiries
  ) public view returns(uint[] memory) {    
    // need to consider that this might be being called to produce expiries for boards inside one another.
    uint latestTimeStamp = Arrays.findUpperBound(liveExpiries, timestamp);
    return _expiriesGenerator(nWeeklies, nMonthlies, latestTimeStamp, lastFridays);
  }

  /**  @notice Called when there are no boards currently deployed.
  * @param lastFridays list of last fridays ordered
  * @param nWeeklies number of weeklies to generate
  * @param nMonthlies number of monthlies to generate
  * @param timestamp current timestamp
  * @return uint[] the return variables of a contract’s function state variable
  */
  function getNewExpiry(
    uint nWeeklies,
    uint nMonthlies,
    uint timestamp,
    uint[] storage lastFridays
  ) public view returns(uint[] memory) {
    return _expiriesGenerator(nWeeklies, nMonthlies, timestamp, lastFridays);
  }

  /** @notice A function that generates a list of expiries
  * @dev Shoudl check for zeroed array indexs
  * @param nWeeklies Number of weeklies to generate
  * @param nMonthlies Number of monthlies to generate
  * @param timestamp The current timestamp
  * @param lastFridays The list of last fridays
  * @return uint[] the array of expiries
  */
  function _expiriesGenerator(
    uint nWeeklies,
    uint nMonthlies,
    uint timestamp,
    uint[] storage lastFridays
  ) internal view returns (uint[] memory) {
    uint[] memory expiries = new uint[](nWeeklies + nMonthlies);

    uint weeklyExpiry = _getNextFriday(timestamp);
    for (uint i = 0; i < nWeeklies; i++) {
      expiries[i] = weeklyExpiry;
      weeklyExpiry += 7 days;
    }
    
    uint monthlyIndex = Arrays.findUpperBound(lastFridays, timestamp);
    uint insertIndex = nWeeklies;
    console2.log("expiries length", expiries.length);
    // if there is more than 1 monthly add to expiries array
    for (uint i = 0; i < nMonthlies; i++) {
      uint monthlyStamp = lastFridays[monthlyIndex + i];
      console2.log("monthly stamp", monthlyStamp);
      if (UnorderedMemoryArray.findInArray(expiries, monthlyStamp, nWeeklies) != -1) {
        // if the weekly expiry is already in the monthlies array
        // then we need to add the next friday
        continue;
      }
      expiries[insertIndex] = monthlyStamp;
      insertIndex++;
    }

    // trims trailing zeros
    assembly {
      mstore(expiries, sub(mload(expiries), sub(add(nWeeklies, nMonthlies), insertIndex)))
    }
    // should think about trimming the array if there are overlaps in the monthlys
    return expiries;
  }

  /////////////
  // Helpers //
  /////////////

  /**  @notice This function finds the first friday relative to the current timestamp
  * @dev Friday's array has to be sorted in ascending order
  * @param timestamp The current timestamp
  * @return Timestamp the timestamp of the closest friday to the current timestamp, 
  */ 
  function _getNextFriday(uint256 timestamp) public pure returns (uint256) {
    uint timezoneOffset = 3600 * 8; // 8 hours in seconds (UTC + 8)

    return timestamp + (5 - (timestamp / 86400 + 4) % 7) * 86400 + timezoneOffset;
  }

  /// errors
}