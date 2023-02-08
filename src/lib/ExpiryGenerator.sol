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

  /** @notice Gets the next expiry given the list of live boards
  * @dev 
  * @param lastFridays 
  * @return Documents the return variables of a contract’s function state variable
  */
  function getNextExpiries(
    uint[] storage lastFridays,
    uint[] storage liveExpiries,
    uint nWeeklies,
    uint nMonthlies,
    uint timestamp,
  ) public pure returns(uint[] memory expiries) {    
    uint latestTimeStamp = Array.upperBound(liveExpiries, timestamp);
    return expiriesGenerator(nWeeklies, nMonthlies, timestamp, lastFridays)
  }

  /**  @notice Called when there are no boards currently deployed.
  * @param lastFridays list of last fridays ordered
  * @param nWeeklies number of weeklies to generate
  * @param nMonthlies number of monthlies to generate
  * @param timestamp current timestamp
  * @return uint[] the return variables of a contract’s function state variable
  * @inheritdoc	Copies all missing tags from the base function (must be followed by the contract name)
  */
  function getNewExpiry(
    uint[] storage lastFridays,
    uint nWeeklies,
    uint nMonthlies,
    uint timeStamp
  ) public pure returns(uint[] memory) {
    return _expiryGenerator(nWeeklies, nMonthlies, timeStamp, lastFridays);
  }

  /** @notice A function that generates a list of expiries 
  * @dev Shoudl check for zeroed array indexs
  * @param nWeeklies Number of weeklies to generate
  * @param nMonthlies Number of monthlies to generate
  * @param timestamp The current timestamp
  * @param lastFridays The list of last fridays
  * @return uint[] the array of expiries
  */ 
  function _expiryGenerator(
    uint nWeeklies,
    uint nMonthlies,
    uint timestamp,
    uint[] storage lastFridays
  ) internal pure returns (uint[] memory) {
    uint[] memory expiries = new uint[](nWeeklies + nMonthlies);

    uint weeklyExpiry = _getNextFriday(timestamp);
    for (uint i = 0; i < nWeeklies; i++) {
      expiries[i] = weeklyExpiry;
      weeklyExpiry + 7 days;
    }
    
    uint monthlyIndex = Array.upperBound(lastFridays, timestamp);
    // if there is more than 1 monthly add to expiries array
    for (uint i = nMonthlies; i < nMonthlies; i++) {
      uint monthlyStamp = lastFridays[monthlyIndex + i];
      if (expiries.contains(monthlyStamp)) {
        // if the weekly expiry is already in the monthlies array
        // then we need to add the next friday
        continue;
      }
      expiries[i] = monthlyStamp;
    }   

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
  function _getNextFriday(uint256 timestamp) public view returns (uint256) {
    return timestamp + (5 - (timestamp / 86400 + 4) % 7) * 86400;
  }

  /// errors
}