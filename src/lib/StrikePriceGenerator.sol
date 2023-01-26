//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

// Libraries
import "newport/synthetix/SignedDecimalMath.sol";
import "newport/synthetix/DecimalMath.sol";
import "newport/libraries/FixedPointMathLib.sol";
import "newport/libraries/BlackScholes.sol";

/**
 * @title Automated strike price generator
 * @author Lyra
 * @notice The library automatically generates strike prices for various expiries as spot fluctuates.
 *         The intent is to automate away the decision making on which strikes to list,
 *         while generating boards with strike price that span a reasonable delta range.
 */
library StrikePriceGenerator {
  using DecimalMath for uint;
  using SignedDecimalMath for int;
  using FixedPointMathLib for int;

  /**
   * @notice Generates an array of new strikes around spot following the schema of this library.
   * @param tTarget The annualized time-to-expiry of the new surface to generate.
   * @param spot Current chainlink spot price.
   * @param maxScaledMoneyness Caller must pre-compute maxScaledMoneyness from governance parameters.
   *                           Typically one param would be a static MAX_D1, e.g. MAX_D1 = 1.2, which would
   *                           be mapped out of the desired delta range. Since delta=N(d1), if we want to bound
   *                           the delta to say (10, 90) range, we can simply bound d1 to be in (-1.2, 1.2) range.
   *                           Second param would be some approx volatility baseline, e.g. MONEYNESS_SCALER.
   *                           This param can be maintained by governance or taken to be some baseIv GVAW.
   *                           It since d1 = ln(K/S) / (sigma * sqrt(T)), some proxy for sigma is needed to
   *                           solve for K from d1.
   *                           Together, maxScaledMoneyness = MAX_D1 * MONEYNESS_SCALER is expected to be passed here.
   * @param maxNumStrikes A cap on how many strikes can be in a single board.
   * @param liveStrikes Array of strikes that already exist in the board, will avoid generating them.
   * @return newStrikes The additional strikes that must be added to the board.
   */
  function getNewStrikes(
    uint tTarget,
    uint spot,
    uint maxScaledMoneyness,
    uint maxNumStrikes,
    uint[] memory liveStrikes,
    uint[] storage pivots
  ) public view returns (uint[] memory newStrikes) {
    // find the ATM strike and see if it already exists
    (uint atmStrike, uint step) = _getATMStrike(pivots, spot, tTarget);
    uint addAtm = !_existsIn(liveStrikes, atmStrike) ? 1 : 0;

    // find remaining strike (excluding atm)
    int remainNumStrikes = int(maxNumStrikes) - int(liveStrikes.length) - int(addAtm);
    if (remainNumStrikes < 0) {
      // if == 0, then still need to add ATM
      return newStrikes;
    }

    // add atm strike first
    newStrikes = new uint[](uint(remainNumStrikes+1));
    if (addAtm == 1) {
      newStrikes[0] = atmStrike;
    }

    // find strike range
    uint strikeRange = int(maxScaledMoneyness.multiplyDecimal(BlackScholes._sqrt(tTarget * DecimalMath.UNIT))).exp();
    uint maxStrike = spot.multiplyDecimal(strikeRange);
    uint minStrike = spot.divideDecimal(strikeRange);

    // starting from ATM strike, go left and right in steps
    bool isLeft = true;
    uint nextStrike;
    uint stepFromAtm;
    for (uint i = 1; i < uint(remainNumStrikes+1); i++) {
      stepFromAtm = i * step;
      if (isLeft) { // prioritize left strike
        nextStrike = (atmStrike > stepFromAtm) 
        ? atmStrike - stepFromAtm
        : 0;
      } else {
        nextStrike = atmStrike + stepFromAtm;
      }

      if (!_existsIn(liveStrikes, nextStrike) && (nextStrike > minStrike) && (nextStrike < maxStrike)) {
        newStrikes[i] = nextStrike;
        remainNumStrikes--;
      }

      if (remainNumStrikes == 0) {
        break;
      }

      isLeft = !isLeft;
    }
  }

  /////////////
  // Helpers //
  /////////////

  /**
   * @notice Finds an ATM strike complying with our pivot/step schema.
   * @dev Consumes up to about 10k gas.
   * @param spot Spot price.
   * @param tAnnualized Years to expiry, 18 decimals.
   * @return strike The first strike satisfying strike <= spot < (strike + step).
   */
  function _getATMStrike(uint[] storage pivots, uint spot, uint tAnnualized) internal view returns (uint strike, uint step) {

    if (spot >= pivots[pivots.length-1]) {
      revert SpotPriceAboveMaxStrike(spot);
    }

    if (spot == 0) {
      revert SpotPriceIsZero(spot);
    }

    strike = _binarySearch(pivots, spot);
    step = _getStep(strike, tAnnualized);
    while (true) {
      // by construction, we start with strike <= spot
      // return the first strike such that strike <= spot < (strike + step)
      // round to the closest between strike and (strike + step)
      // TODO simplification candidate - can have a convention to round to left
      // but then probably change the left/right fill priority to be right (currently left is added first)
      if (spot < strike + step) {
        uint distanceLeft = spot - strike;
        uint distanceRight = (strike + step) - spot;
        strike = (distanceRight < distanceLeft) ? strike + step : strike;
        return (strike, step);
      }
      strike += step;
    }  
  }

  /**
   * @notice Returns the strike step corresponding to the pivot bucket and the time-to-expiry.
   * @dev Since vol is approx ~ sqrt(T), it makes sense to double the step size
   *      every time tAnnualized is roughly quadripled
   * @param p The pivot strike.
   * @param tAnnualized Years to expiry, 18 decimals.
   * @return step The strike step size at this pivot and tAnnualized.
   */
  function _getStep(uint p, uint tAnnualized) internal pure returns (uint step) {
    unchecked {
      // TODO make these magic numbers into params, e.g. struct/duoble array as input?
      uint div;
      if (tAnnualized * (365 days) <= (1 weeks * 1e18)) div = 40;
      else if (tAnnualized * (365 days) <= (4 weeks * 1e18)) div = 20;
      else if (tAnnualized * (365 days) <= (12 weeks * 1e18)) div = 10;
      else div = 5;
      step = p / div;
      // floor step at 1e-18 in case the pivot supplied is too small and the div rounds to 0
      step = (step == 0) ? 1 : step;
      return step;
    }
  }

  ///////////////////
  // Array Helpers //
  ///////////////////

  /// copied from GWAV.sol
  function _binarySearch(uint[] storage pivots, uint spot) internal view returns (uint leftNearest) {
    uint leftPivot;
    uint rightPivot;
    uint leftBound = 0;
    uint rightBound = pivots.length;
    uint i;
    while (true) {
      i = (leftBound + rightBound) / 2;
      leftPivot = pivots[i];
      rightPivot = pivots[i + 1];

      bool onRightHalf = leftPivot <= spot;

      // check if we've found the answer!
      if (onRightHalf && spot <= rightPivot) break;

      // otherwise start next search iteration
      if (!onRightHalf) {
        rightBound = i - 1;
      } else {
        leftBound = i + 1;
      }
    }

    return leftPivot;
  }


  /**
   * @notice Searches for an exact match of target in values[].
   * @param values An array of uint values.
   * @param target Target value to search.
   * @return idx Index of target in values[].
   */
  function _indexOf(uint[] memory values, uint target) internal pure returns (uint idx) {
    unchecked {
      for (uint i = 0; i < values.length; i++) {
        if (target == values[i]) return i;
      }
      return values.length;
    }
  }

  /**
   * @notice Searches for an exact match of target in values[], and returns true if exists.
   * @param values An array of uint values.
   * @param target Target value to search.
   * @return exists Bool, true if exists.
   */
  function _existsIn(uint[] memory values, uint target) internal pure returns (bool exists) {
    unchecked {
      return (_indexOf(values, target) != values.length);
    }
  }

  ////////////
  // Errors //
  ////////////
  error SpotPriceAboveMaxStrike(uint spot);
  error SpotPriceIsZero(uint spot);
}
