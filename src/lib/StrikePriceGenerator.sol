//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

// Libraries
import "newport/synthetix/SignedDecimalMath.sol";
import "newport/synthetix/DecimalMath.sol";
import "newport/libraries/FixedPointMathLib.sol";
import "newport/libraries/BlackScholes.sol";

import "forge-std/console2.sol";

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
    // find step size and the nearest pivot
    uint nearestPivot = getLeftNearestPivot(pivots, spot);
    uint step = getStep(nearestPivot, tTarget);

    // find the ATM strike and see if it already exists
    (uint atmStrike) = getATMStrike(spot, nearestPivot, step);
    uint addAtm = !_existsIn(liveStrikes, atmStrike) ? 1 : 0;

    // find remaining strike (excluding atm)
    int remainNumStrikes = int(maxNumStrikes) - int(liveStrikes.length);
    if (remainNumStrikes <= 0) {
      // if == 0, then still need to add ATM
      return newStrikes;
    }

    // add atm strike first
    newStrikes = new uint[](uint(remainNumStrikes));
    if (addAtm == 1) {
      newStrikes[0] = atmStrike;
      remainNumStrikes--;
    }

    // find strike range
    (uint minStrike, uint maxStrike) = getStrikeRange(tTarget, spot, maxScaledMoneyness);

    // starting from ATM strike, go left and right in steps
    bool isLeft = true;
    uint nextStrike;
    uint stepFromAtm;
    uint i = 0;
    uint numAdded = addAtm;
    while (remainNumStrikes > 0) {
      stepFromAtm = (1 + (i / 2)) * step;
      if (isLeft) {
        // prioritize left strike
        nextStrike = (atmStrike > stepFromAtm) ? atmStrike - stepFromAtm : 0;
      } else {
        nextStrike = atmStrike + stepFromAtm;
      }

      if (!_existsIn(liveStrikes, nextStrike) && (nextStrike > minStrike) && (nextStrike < maxStrike)) {
        newStrikes[numAdded++] = nextStrike;
        remainNumStrikes--;
      }

      isLeft = !isLeft;
      i++;
    }
  }

  /////////////
  // Helpers //
  /////////////

  /**
   * @notice Finds the left nearest pivot using binary search
   * @param pivots Storage array of available pivots
   * @param spot Spot price
   * @return nearestPivot left nearest pivot
   */
  function getLeftNearestPivot(uint[] storage pivots, uint spot) public view returns (uint nearestPivot) {
    uint maxPivot = pivots[pivots.length - 1];
    if (spot >= maxPivot) {
      revert SpotPriceAboveMaxStrike(maxPivot);
    }

    if (spot == 0) {
      revert SpotPriceIsZero();
    }

    // finds the nearest pivot
    return _binarySearch(pivots, spot);
  }

  /**
   * @notice Finds the ATM strike by stepping up from the pivot
   * @param spot Spot price
   * @param pivot Pivot strike that is nearest to the spot price
   * @param step Step size
   * @return atmStrike The first strike satisfying strike <= spot < (strike + step)
   */
  function getATMStrike(uint spot, uint pivot, uint step) public pure returns (uint atmStrike) {
    atmStrike = pivot;
    while (true) {
      uint nextStrike = atmStrike + step;

      if (spot < nextStrike) {
        uint distanceLeft = spot - atmStrike;
        uint distanceRight = nextStrike - spot;
        return (distanceRight < distanceLeft) ? nextStrike : atmStrike;
      }
      atmStrike += step;
    }
  }

  function getStrikeRange(uint tTarget, uint spot, uint maxScaledMoneyness)
    public
    pure
    returns (uint minStrike, uint maxStrike)
  {
    uint strikeRange = int(maxScaledMoneyness.multiplyDecimal(BlackScholes._sqrt(tTarget * DecimalMath.UNIT))).exp();
    return (spot.divideDecimal(strikeRange), spot.multiplyDecimal(strikeRange));
  }

  /**
   * @notice Returns the strike step corresponding to the pivot bucket and the time-to-expiry.
   * @dev Since vol is approx ~ sqrt(T), it makes sense to double the step size
   *      every time tAnnualized is roughly quadripled
   * @param p The pivot strike.
   * @param tAnnualized Years to expiry, 18 decimals.
   * @return step The strike step size at this pivot and tAnnualized.
   */
  function getStep(uint p, uint tAnnualized) public pure returns (uint step) {
    unchecked {
      uint div;
      if (tAnnualized * (365 days) <= (1 weeks * 1e18)) {
        div = 40; // 2.5%
      } else if (tAnnualized * (365 days) <= (4 weeks * 1e18)) {
        div = 20; // 5%
      } else if (tAnnualized * (365 days) <= (12 weeks * 1e18)) {
        div = 10; // 10%
      } else {
        div = 5; // 20%
      }

      if (p <= div) {
        revert PivotLessThanOrEqualToStepDiv(p, div);
      }
      return p / div;
    }
  }

  ///////////////////
  // Array Helpers //
  ///////////////////

  /// copied from GWAV.sol
  // todo: should reuse V2 ArrayLib and add these in there.
  function _binarySearch(uint[] storage sortedArray, uint target) internal view returns (uint leftNearest) {
    uint leftPivot;
    uint rightPivot;
    uint leftBound = 0;
    uint rightBound = sortedArray.length;
    uint i;
    while (true) {
      i = (leftBound + rightBound) / 2;
      leftPivot = sortedArray[i];
      rightPivot = sortedArray[i + 1];

      bool onRightHalf = leftPivot <= target;
      bool onLeftHalf = target <= rightPivot;

      // check if we've found the answer!
      if (onRightHalf && onLeftHalf) {
        return (target == rightPivot) ? rightPivot : leftPivot;
      }

      // otherwise start next search iteration
      if (!onRightHalf) {
        rightBound = i - 1;
      } else {
        leftBound = i + 1;
      }
    }
  }

  /**
   * @notice Searches for an exact match of target in values[], and returns true if exists.
   * @param values An array of uint values.
   * @param target Target value to search.
   * @return exists Bool, true if exists.
   */
  function _existsIn(uint[] memory values, uint target) internal pure returns (bool exists) {
    for (uint i = 0; i < values.length; i++) {
      if (target == values[i]) return true;
    }

    return false;
  }

  ////////////
  // Errors //
  ////////////
  error SpotPriceAboveMaxStrike(uint maxPivot);
  error SpotPriceIsZero();
  error PivotLessThanOrEqualToStepDiv(uint pivot, uint div);
}
