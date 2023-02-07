//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

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
  

  /**
  * 
   */
  function getNextExpiries(
    uint tTarget,
    uint spot,
    uint maxScaledMoneyness,
    uint maxNumStrikes,
    uint[] memory liveStrikes,
    uint[] storage pivots
  ) public returns(uint) {
    // TODO: gets current latest board and then finds next expiry on the friday
  }

  function getNewExpiry() returns(uint) {
    // TODO: given no live boards it finds the next friday from the current timestamp, given a buffer,
    //      and then returns that timestamp
  }
  
}