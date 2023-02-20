//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "../../lib/openzeppelin-contracts/contracts/utils/Arrays.sol";
import "../../lib/lyra-utils/src/arrays/UnorderedMemoryArray.sol";

/**
 * @title Automated Expiry Generator
 * @author Lyra
 * @notice This Library automatically generates expiry times for various boards
 * The intent being to automate the way that boards and strikes are listed
 * Whilst ensuring that the expiries make sense are in reasonable timeframes
 */
library ExpiryGenerator {
  /// @dev time difference between 0 UTC and the friday 8am
  uint constant MOD_OFFSET = 115200;

  /**
   * @notice Calculate the upcoming weekly and monthly expiries and insert into an array.
   * @param monthlyExpiries Ordered list of monthly expiries
   * @param nWeeklies Number of weekly options to generate
   * @param nMonthlies Number of monthly options to generate
   * @param timestamp Reference timestamp for generating expiries from that date onwards
   * @return expiries The valid expiries for the given parameters
   */
  function getExpiries(uint nWeeklies, uint nMonthlies, uint timestamp, uint[] storage monthlyExpiries)
    internal
    view
    returns (uint[] memory expiries)
  {
    return _expiriesGenerator(nWeeklies, nMonthlies, timestamp, monthlyExpiries);
  }

  function _expiriesGenerator(uint nWeeklies, uint nMonthlies, uint timestamp, uint[] storage monthlyExpiries)
    internal
    view
    returns (uint[] memory expiries)
  {
    expiries = new uint[](nWeeklies + nMonthlies);
    uint weeklyExpiry = getNextFriday(timestamp);

    uint insertIndex = 0;
    for (; insertIndex < nWeeklies; ++insertIndex) {
      expiries[insertIndex] = weeklyExpiry;
      weeklyExpiry += 7 days;
    }

    // TODO: consider if we want to start from last weekly seen and get _next_ 3 monthlies
    uint monthlyIndex = Arrays.findUpperBound(monthlyExpiries, timestamp);

    // if there is more than 1 monthly add to expiries array
    for (uint i = 0; i < nMonthlies; i++) {
      uint monthlyStamp = monthlyExpiries[monthlyIndex + i];
      if (UnorderedMemoryArray.findInArray(expiries, monthlyStamp, nWeeklies) != -1) {
        // if the weekly expiry is already in the monthlies array
        // then we need to add the next friday
        continue;
      }
      expiries[insertIndex] = monthlyStamp;
      ++insertIndex;
    }

    UnorderedMemoryArray.trimArray(expiries, insertIndex);

    return expiries;
  }

  /////////////
  // Helpers //
  /////////////

  /**
   * @notice This function finds the first friday expiry (8pm UTC) relative to the current timestamp
   * @dev Friday's array has to be sorted in ascending order
   * @param timestamp The current timestamp
   * @return Timestamp the timestamp of the closest friday to the current timestamp,
   */
  function getNextFriday(uint timestamp) internal view returns (uint) {
    // by adding the offset you make the friday 8am the reference point - so when you mod, you'll round to the nearest friday
    return timestamp - ((timestamp - MOD_OFFSET) % 7 days) + 7 days;
  }
}
