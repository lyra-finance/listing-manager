//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

// Libraries
import "newport/synthetix/SignedDecimalMath.sol";
import "newport/synthetix/DecimalMath.sol";
import "newport/libraries/FixedPointMathLib.sol";
import "newport/libraries/BlackScholes.sol";
import "newport/libraries/Math.sol";

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
  using FixedPointMathLib for uint;
  using FixedPointMathLib for int;

  /// @dev For strike extrapolation, slope of totalVol(log-moneyness) is known to be bounded
  ///      by 2 from Roger-Lee formula for large enough strikes
  ///      we adopt this bound for all strike extrapolations to avoid unexpected overshooting
  int private constant MAX_STRIKE_EXTRAPOLATION_SLOPE = 2e18;
  uint private constant UNIT = 1e18;
  // when queriying nth element of the strike schema, n is capped at MAX_PIVOT_INDEX to avoid overflow
  uint private constant MAX_PIVOT_INDEX = 200;
  // value of the pivot at n = (MAX_PIVOT_INDEX+1), add 1 since we want the right point of the bucket
  uint private constant MAX_PIVOT = 10 ** 67;

  struct StrikeData {
    // strike price
    uint strikePrice;
    // volatility component specific to the strike listing (boardIv * skew = vol of strike)
    uint skew;
  }

  struct ExpiryData {
    // The annualized time when the board expires.
    uint tAnnualized;
    // The initial value for baseIv (baseIv * skew = strike volatility).
    uint baseIv;
    // An array of strikes (strike prices and skews) belonging to this expiry
    StrikeData[] strikes;
  }

  function createBoard(
    ExpiryData[] memory expiryArray,
    uint tTarget, // TODO write up expiry schema and force createBoard() to use that schema as opposed to tTarget?
    uint spot,
    uint maxScaledMoneyness,
    uint maxNumStrikes,
    uint forceATMSkew,
    uint[] storage pivots
  ) public view returns (uint[] memory strikes) {
    // TODO uint tTarget = getSchemaExpiry(expiryArray,...)
    uint[] memory liveStrikes = new uint[](0);
    strikes = getSchemaStrikes(tTarget, spot, maxScaledMoneyness, maxNumStrikes, liveStrikes, pivots);
  }

  function extendBoard(
    ExpiryData memory expiryData, 
    uint spot, 
    uint maxScaledMoneyness, 
    uint maxNumStrikes,
    uint[] storage pivots
)
    public
    view
    returns (uint[] memory strikes)
  {
    uint[] memory liveStrikes = new uint[](expiryData.strikes.length);
    for (uint i; i < expiryData.strikes.length; i++) {
      liveStrikes[i] = expiryData.strikes[i].strikePrice;
    }
    strikes = getSchemaStrikes(expiryData.tAnnualized, spot, maxScaledMoneyness, maxNumStrikes, liveStrikes, pivots);
  }

  /**
   * @notice Generates an array of strikes around spot following the schema of this library.
   * @dev Caller must pre-compute maxScaledMoneyness from the governance parameters.
   *      Typically one param would be a static MAX_D1, e.g. MAX_D1 = 1.2, which would
   *      be mapped out of the desired delta range. Since delta=N(d1), if we want to bound
   *      the delta to say (10, 90) range, we can simply bound d1 to be in (-1.2, 1.2) range.
   *      Second param would be some approx volatility baseline, e.g. MONEYNESS_SCALER.
   *      This param can be maintained by governance or taken to be some baseIv GVAW.
   *      It since d1 = ln(K/S) / (sigma * sqrt(T)), some proxy for sigma is needed to
   *      solve for K from d1.
   *      Together, maxScaledMoneyness = MAX_D1 * MONEYNESS_SCALER is expected to be passed here.
   * @param tTarget The annualized time-to-expiry of the new surface to generate.
   * @param spot Current chainlink spot price.
   * @param maxScaledMoneyness Max vol-scaled moneyness to generates strike until.
   * @param maxNumStrikes A cap on how many strikes can be in a single board.
   * @param liveStrikes Array of strikes that already exist in the board, will avoid generating them.
   * @return strikes The strikes for the new surface following the schema of this library.
   */
  function getSchemaStrikes(
    uint tTarget,
    uint spot,
    uint maxScaledMoneyness,
    uint maxNumStrikes,
    uint[] memory liveStrikes,
    uint[] storage pivots
  ) public view returns (uint[] memory strikes) {
    // todo [Josh]: should return new strikes, instead of total strikes? Or maybe both
    uint remainNumStrikes = maxNumStrikes > liveStrikes.length ? maxNumStrikes - liveStrikes.length : uint(0);
    if (remainNumStrikes == 0) return new uint[](0);
    uint atmStrike;
    uint step;
    (atmStrike, step) = _findATMStrike(pivots, spot, tTarget);
    uint maxStrike;
    uint minStrike;
    {
      uint strikeScaler = int(maxScaledMoneyness.multiplyDecimal(BlackScholes._sqrt(tTarget * UNIT))).exp();
      maxStrike = spot.multiplyDecimal(strikeScaler);
      minStrike = spot.divideDecimal(strikeScaler);
    }
    bool addAtm = (!_existsIn(liveStrikes, atmStrike));
    // remainNumStrikes == 0 is handled above, subbing 1 is safe
    remainNumStrikes -= (addAtm ? uint(1) : uint(0));
    uint[] memory strikesLeft = new uint[](remainNumStrikes);
    uint[] memory strikesRight = new uint[](remainNumStrikes);
    uint nLeft;
    uint nRight;
    // starting from ATM strike, go left and right in steps of step
    // record a new strike if it does not exist in liveStrikes and if it is within min/max bounds
    for (uint i = 0; i < remainNumStrikes; i++) {
      // todo [Josh]: can probably remove this if by formatting pivots differently
      uint newLeft = (atmStrike > (i + 1) * step) ? atmStrike - (i + 1) * step : uint(0);
      uint newRight = atmStrike + (i + 1) * step;
      if (remainNumStrikes - nLeft - nRight == 0) break;
      // todo [Josh]: newLeft > 0 is guaranteed
      if (!_existsIn(liveStrikes, newLeft) && (newLeft > minStrike) && (newLeft > 0)) {
        strikesLeft[i] = newLeft;
        nLeft++;
      }
      // quirk: if there's 1 strike remaining, the left is added first, the below can break the loop
      // this means left strikes are somewhat "prioritized"
      if (remainNumStrikes - nLeft - nRight == 0) break;
      if (!_existsIn(liveStrikes, newRight) && (newRight < maxStrike)) {
        strikesRight[i] = newRight;
        nRight++;
      }
    }
    // fill in strikes array, maintaining the sorted order
    // todo [Josh]: can probably do this in place somehow
    strikes = new uint[](nLeft + nRight + (addAtm ? uint(1) : uint(0)));
    if (addAtm) strikes[nLeft] = atmStrike;
    for (uint i = 0; i < strikesLeft.length; i++) {
      if (strikesLeft[i] != 0) {
        nLeft--;
        strikes[nLeft] = strikesLeft[i];
      }
    }
    for (uint i = 0; i < strikesRight.length; i++) {
      if (strikesRight[i] != 0) {
        nRight--;
        strikes[strikes.length - nRight - 1] = strikesRight[i];
      }
    }
  }

  /**
   * @notice Searches for an index such that inserting target at that index preserves array order.
   * @dev this is equivalent in output & behaviour to numpy's `left` searchsorted
   *      https://numpy.org/doc/stable/reference/generated/numpy.searchsorted.html
   * @param values A sorted array of uint values.
   * @param target Target value to search.
   * @return idx Index in values array such that inserting target at that index would preserve sorting.
   */
  function _searchSorted(uint[] memory values, uint target) internal view returns (uint idx) {
    unchecked {
      if (target <= values[0]) return 0;
      if (target > values[values.length - 1]) return values.length;
      for (uint i = 0; i < values.length - 1; i++) {
        if ((target > values[i]) && (target <= values[i + 1])) return (i + 1);
      }
      return values.length; // this should never happen since the above captures all cases
    }
  }

  /**
   * @notice Searches for an exact match of target in values[].
   * @param values An array of uint values.
   * @param target Target value to search.
   * @return idx Index of target in values[].
   */
  function _indexOf(uint[] memory values, uint target) internal view returns (uint idx) {
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
  function _existsIn(uint[] memory values, uint target) internal view returns (bool exists) {
    unchecked {
      return (_indexOf(values, target) != values.length);
    }
  }

  /**
   * @notice Searches for an arg min of an array.
   * @param values An array of uint values.
   * @return idx Index of the smallest element.
   */
  function _argMin(uint[] memory values) internal view returns (uint idx) {
    unchecked {
      uint min = values[0];
      for (uint i = 1; i < values.length; i++) {
        if (values[i] < min) {
          idx = i;
          min = values[i];
        }
      }
    }
  }

  /**
   * @notice Sorts an array of ExpiryData by expiry (in-place)
   * @param data ExpiryData[] array to sort
   */
  function _sortExpiry(ExpiryData[] memory data) internal view {
    if (data.length > 1) {
      _quickSortExpiry(data, 0, data.length - 1);
    }
  }

  /**
   * @notice Quicksort implementation of _sortExpiry()
   */
  function _quickSortExpiry(ExpiryData[] memory data, uint low, uint high) internal view {
    unchecked {
      if (low < high) {
        uint pivotVal = data[(low + high) / 2].tAnnualized;

        uint low1 = low;
        uint high1 = high;
        for (;;) {
          while (data[low1].tAnnualized < pivotVal) low1++;
          while (data[high1].tAnnualized > pivotVal) high1--;
          if (low1 >= high1) break;
          (data[low1], data[high1]) = (data[high1], data[low1]);
          low1++;
          high1--;
        }
        if (low < high1) _quickSortExpiry(data, low, high1);
        high1++;
        if (high1 < high) _quickSortExpiry(data, high1, high);
      }
    }
  }

  /**
   * @notice Sorts an array of StrikeData by expiry (in-place)
   * @param data A StrikeData array to sort
   */
  function _sortStrike(StrikeData[] memory data) internal view {
    if (data.length > 1) {
      _quickSortStrike(data, 0, data.length - 1);
    }
  }

  /**
   * @notice Quicksort implementation of _sortStrike()
   */
  function _quickSortStrike(StrikeData[] memory data, uint low, uint high) internal view {
    unchecked {
      if (low < high) {
        uint pivotVal = data[(low + high) / 2].strikePrice;

        uint low1 = low;
        uint high1 = high;
        for (;;) {
          while (data[low1].strikePrice < pivotVal) low1++;
          while (data[high1].strikePrice > pivotVal) high1--;
          if (low1 >= high1) break;
          (data[low1], data[high1]) = (data[high1], data[low1]);
          low1++;
          high1--;
        }
        if (low < high1) _quickSortStrike(data, low, high1);
        high1++;
        if (high1 < high) _quickSortStrike(data, high1, high);
      }
    }
  }

  /**
   * @notice Converts a $ strike to standard moneyness.
   * @dev By "standard" moneyness we mean moneyness := ln(K/S) / sqrt(T).
   *      This value allows us to avoid delta calculations.
   *      Delta maps one-to-one to Black-Scholes d1, and this is a "simple" version of d1.
   *      So instead of using / computing / inverting delta, we can just find moneyness
   *      That maps to desired delta values, and use it instead.
   * @param strike dollar strike, 18 decimals
   * @param spot dollar Chainlink spot, 18 decimals
   * @param tAnnualized annualized time-to-expiry, 18 decimals
   */
  function _strikeToMoneyness(uint strike, uint spot, uint tAnnualized) internal view returns (int moneyness) {
    unchecked {
      moneyness = int(strike.divideDecimal(spot)).ln().divideDecimal(int(BlackScholes._sqrt(tAnnualized * UNIT)));
    }
  }

  /**
   * @notice Converts standard moneyness back to a $ strike.
   * @dev Literally "undoes" _strikeToMoneyness()
   * @param moneyness moneyness as defined in _strikeToMoneyness()
   * @param spot dollar Chainlink spot, 18 decimals
   * @param tAnnualized annualized time-to-expiry, 18 decimals
   */
  function _moneynessToStrike(int moneyness, uint spot, uint tAnnualized) internal view returns (uint strike) {
    unchecked {
      strike = moneyness.multiplyDecimal(int(BlackScholes._sqrt(tAnnualized * UNIT))).exp().multiplyDecimal(spot);
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
  function _strikeStep(uint p, uint tAnnualized) internal view returns (uint step) {
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

  /**
   * @notice Finds an ATM strike complying with our pivot/step schema.
   * @dev Consumes up to about 10k gas.
   * @param spot Spot price.
   * @param tAnnualized Years to expiry, 18 decimals.
   * @return strike The first strike satisfying strike <= spot < (strike + step).
   */
  function _findATMStrike(uint[] storage pivots, uint spot, uint tAnnualized) internal view returns (uint strike, uint step) {
    unchecked {
      strike = _findNearestPivot(pivots, spot);
      step = _strikeStep(strike, tAnnualized);
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
  }

  /**
   * @notice Returns the index of the pivot bucket the spot belongs to (i.e. p(n) <= spot < p(n+1)).
   * @param spot Spot price.
   * @return n The index of the pivot bucket the spot belongs to.
   */

  function _findNearestPivot(uint[] storage pivots, uint spot) internal view returns (uint) {
    if (spot >= MAX_PIVOT) {
      revert SpotPriceAboveMaxStrike(spot);
    }

    if (spot == 0) {
      revert SpotPriceIsZero(spot);
    }

    return _binarySearch(pivots, spot);

  }


  /// copied from GWAV.sol
  function _binarySearch(uint[] storage pivots, uint spot) internal view returns (uint leftNearest) {
    uint leftPivot;
    uint rightPivot;
    uint leftBound;
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

  ////////////
  // Errors //
  ////////////
  error EmptyStrikes();
  error EmptyExpiries();

  error StrikeAlreadyExists(uint newStrike);
  error ExpiryAlreadyExists(uint newExpiry);

  error ZeroATMSkewNotAllowed();

  error PivotIndexAboveMax(uint n);
  error SpotPriceAboveMaxStrike(uint spot);
  error SpotPriceIsZero(uint spot);
}
