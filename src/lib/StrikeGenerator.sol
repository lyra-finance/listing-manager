//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

// Libraries
import "../synthetix/SignedDecimalMath.sol";
import "../synthetix/DecimalMath.sol";
import "./FixedPointMathLib.sol";
import "./BlackScholes.sol";
import "./Math.sol";

/**
 * @title Automated Strikes and Expiries Manager
 * @author Lyra
 * @dev The library works with in-memory ExpiryData and StrikeData structs that must be mapped from option boards.
 *
 * It is used to generate new skews and baseIvs from these data structs (for new strikes / expiries).
 * It is also used to generate $ strike numbers based on a [1,2,5,10,20,50,100,...] strike sequence schema.
 */
library AutoStrikes {
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
  uint private constant MAX_PIVOT = 10**67;

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
    uint forceATMSkew
  ) public view returns (uint baseIv, uint[] memory strikes, uint[] memory skews) {
    // TODO uint tTarget = getSchemaExpiry(expiryArray,...)
    uint[] memory liveStrikes = new uint[](0);
    strikes = getSchemaStrikes(tTarget, spot, maxScaledMoneyness, maxNumStrikes, liveStrikes);
    (baseIv, skews) = getVolsForExpiry(expiryArray, tTarget, strikes, spot, forceATMSkew);
  }

  function extendBoard(
    ExpiryData memory expiryData,
    uint spot,
    uint maxScaledMoneyness,
    uint maxNumStrikes
  ) public view returns (uint[] memory strikes, uint[] memory skews) {
    uint[] memory liveStrikes = new uint[](expiryData.strikes.length);
    for (uint i; i < expiryData.strikes.length; i++) {
      liveStrikes[i] = expiryData.strikes[i].strikePrice;
    }
    strikes = getSchemaStrikes(expiryData.tAnnualized, spot, maxScaledMoneyness, maxNumStrikes, liveStrikes);
    skews = _getSkewForStrikeArray(expiryData, strikes, true);
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
    uint[] memory liveStrikes
  ) public view returns (uint[] memory strikes) {
    // todo [Josh]: should return new strikes, instead of total strikes? Or maybe both
    uint remainNumStrikes = maxNumStrikes > liveStrikes.length ? maxNumStrikes - liveStrikes.length : uint(0);
    if (remainNumStrikes == 0) return new uint[](0);
    uint atmStrike;
    uint step;
    (atmStrike, step) = _findATMStrike(spot, tTarget);
    uint maxStrike;
    uint minStrike;
    {
      uint strikeScaler = int(maxScaledMoneyness.multiplyDecimal(sqrt(tTarget))).exp();
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
    for (uint i=0; i<remainNumStrikes; i++) {
      // todo [Josh]: can probably remove this if by formatting pivots differently
      uint newLeft = (atmStrike > (i+1)*step) ? atmStrike - (i+1)*step : uint(0);
      uint newRight = atmStrike + (i+1)*step;
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
    for (uint i=0; i<strikesLeft.length; i++) {
      if (strikesLeft[i] != 0) {
        nLeft--;
        strikes[nLeft] = strikesLeft[i];
      }
    }
    for (uint i=0; i<strikesRight.length; i++) {
      if (strikesRight[i] != 0) {
        nRight--;
        strikes[strikes.length-nRight-1] = strikesRight[i];
      }
    }
  }

  /** 
   * @notice Generates baseIv and an array of skews for a new expiry.
   * @param expiryArray The "live" volatility surface in the form of ExpiryData[].
   * @param tTarget The annualized time-to-expiry of the new surface user wants to generate.
   * @param strikeTargets The strikes for the new surface user wants to generate (in $ form, 18 decimals).
   * @param spot Current chainlink spot price.
   * @param forceATMSkew Value for ATM skew to anchor towards, e.g. 1e18 will ensure ATM skew is set to 1.0.
   * @return baseIv BaseIV for the new board.
   * @return skews Array of skews for each strike in strikeTargets.
   */
  function getVolsForExpiry(
    ExpiryData[] memory expiryArray,
    uint tTarget,
    uint[] memory strikeTargets,
    uint spot,
    uint forceATMSkew // TODO Can we assume strikeTargets always contains "ATM-ish" strike?
  ) public view returns (uint baseIv, uint[] memory skews) {

    if (expiryArray.length == 0) revert EmptyExpiries();
    if (forceATMSkew == 0) revert ZeroATMSkewNotAllowed();

    // TODO can we assume the expiries are already fully sorted? Going to depend on the process of mapping
    // boards from storage to memory.
    _sortExpiry(expiryArray);
    uint idx;
    {
      uint[] memory tValues = new uint[](expiryArray.length);
      for (uint i; i < expiryArray.length; i++) {
        tValues[i] = expiryArray[i].tAnnualized;
      }
      // try to find exact match and revert if found
      idx = _indexOf(tValues, tTarget);
      if (idx != tValues.length) revert ExpiryAlreadyExists(tTarget);
      idx = _searchSorted(tValues, tTarget);
    }
    if (idx == 0) {
      return _extrapolateExpiry(expiryArray, 0, tTarget, strikeTargets, spot, forceATMSkew);
    }
    if (idx == expiryArray.length) {
      return _extrapolateExpiry(expiryArray, idx-1, tTarget, strikeTargets, spot, forceATMSkew);
    }
    return _interpolateExpiry(expiryArray, idx, tTarget, strikeTargets, spot, forceATMSkew);
  }

  /** 
   * @notice Generates a skew for a new strike from a "live" vol slice.
   * @dev TODO Do we need revertIfAlreadyExists? Should the caller do all of these checks by themselves?
   * @param expiryData The "live" volatility slice in the form of ExpiryData.
   * @param strikeTarget The new strike for which skew is reqeusted (in $ form, 18 decimals).
   * @param revertIfAlreadyExists A flag to revert the tx if strikeTarget already exists in expiryData.
   * @return skew New strike's skew.
   */
  function getSkewForStrike(
    ExpiryData memory expiryData,
    uint strikeTarget,
    bool revertIfAlreadyExists
  ) public view returns (uint skew) {
    if (expiryData.strikes.length == 0) revert EmptyStrikes();
    if (expiryData.strikes.length == 1) return expiryData.strikes[0].skew;
    
    uint[] memory strikeValues = new uint[](expiryData.strikes.length);
    for (uint i; i < expiryData.strikes.length; i++) {
      strikeValues[i] = expiryData.strikes[i].strikePrice;
    }
    // try to find exact match
    uint idx = _indexOf(strikeValues, strikeTarget);
    if (idx != expiryData.strikes.length) {
      if (revertIfAlreadyExists) revert StrikeAlreadyExists(strikeTarget);
      else return expiryData.strikes[idx].skew;
    } 
    // if failed, interpolate / extrapolate
    // ASSUME expiryData is already sorted!!!
    idx = _searchSorted(strikeValues, strikeTarget);
    if (idx == 0) {
      return _extrapolateStrike(expiryData, 0, strikeTarget);
    }
    if (idx == strikeValues.length) {
      return _extrapolateStrike(expiryData, idx-1, strikeTarget);
    }
    return _interpolateStrike(expiryData, idx, strikeTarget);
  }

  /** 
   * @notice Interpolates a skew for a new strike from a "live" vol slice.
   * @param expiryData The "live" volatility slice in the form of ExpiryData.
   * @param idx The index of expiryData.strikes[] such that (strikes[idx-1] < newStrike <= strikes[idx])
   * @param newStrike The new strike for which skew is reqeusted (in $ form, 18 decimals).
   * @return newSkew New strike's skew.
   */
  function _interpolateStrike(
    ExpiryData memory expiryData,
    uint idx,
    uint newStrike
  ) internal view returns (uint newSkew) {
      uint wRight = expiryData.baseIv.multiplyDecimal(expiryData.strikes[idx].skew);
      wRight = wRight.multiplyDecimal(wRight);
      uint wLeft = expiryData.baseIv.multiplyDecimal(expiryData.strikes[idx-1].skew);
      wLeft = wLeft.multiplyDecimal(wLeft);
      int kRight = int(expiryData.strikes[idx].strikePrice).ln();
      int kLeft = int(expiryData.strikes[idx-1].strikePrice).ln();
      int kLMid = int(newStrike).ln();
      int yLeft = (kRight - kLMid).divideDecimal(kRight - kLeft);
      yLeft = yLeft > int(UNIT) ? int(UNIT) : yLeft;
      yLeft = yLeft < int(0) ? int(0) : yLeft;
      return sqrt(uint(yLeft).multiplyDecimal(wLeft) + uint(int(UNIT) - yLeft).multiplyDecimal(wRight)
      ).divideDecimal(expiryData.baseIv);
  }

  /** 
   * @notice Extrapolates a skew for a new strike from a "live" vol slice.
   * @param expiryData The "live" volatility slice in the form of ExpiryData.
   * @param idx The index of the edge of expiryData.strikes[], either 0 or expiryData.strikes.length - 1
   * @param newStrike The new strike for which skew is reqeusted (in $ form, 18 decimals).
   * @return newSkew New strike's skew.
   */
  function _extrapolateStrike(
    ExpiryData memory expiryData,
    uint idx,
    uint newStrike
  ) internal view returns (uint newSkew) {
      int slope;
      // total variance and log-strike of the "edge" (leftmost or rightmost) 
      uint w2 = expiryData.baseIv.multiplyDecimal(expiryData.strikes[idx].skew);
      w2 = w2.multiplyDecimal(w2).multiplyDecimal(expiryData.tAnnualized);
      int k2 = int(expiryData.strikes[idx].strikePrice).ln();
      {
        // block this out to resolve "stack too deep", we don't need w1 and k1 after slope is known
        // TODO do we need to handle k2 == k1? Should never happen but what if
        // total variance and log-strike of the second last element with respect to the edge
        // TODO also maybe rename the 1,2,3 convention lol
        uint idx1 = (idx == 0) ? 1 : idx - 1;
        uint w1 = expiryData.baseIv.multiplyDecimal(expiryData.strikes[idx1].skew);
        w1 = w1.multiplyDecimal(w1).multiplyDecimal(expiryData.tAnnualized);
        int k1 = int(expiryData.strikes[idx1].strikePrice).ln();
        slope = (int(w2)-int(w1)).divideDecimal(int(Math.abs(k2-k1)));
        // By construction, slope is expected to be positive (vol increaes in the tails), hence floor at 0
        // In absolute terms, slope is capped at MAX_STRIKE_EXTRAPOLATION_SLOPE
        /// TODO a rug candidate -> can think if we can just flat-extrapolate strikes
        /// (not gonna expect much of an error in 10-90 delta range)
        /// then no need to compute slope, have 2 strikes, etc.
        /// traders mostly short tails anyway, AMM doesn't want to be a buyer (?)
        slope = (slope > 0) ? slope : int(0);
        slope = (slope > MAX_STRIKE_EXTRAPOLATION_SLOPE) ? MAX_STRIKE_EXTRAPOLATION_SLOPE : slope;
      }
      int k3 = int(newStrike).ln();
      uint w3 = w2 + Math.abs(k3-k2).multiplyDecimal(uint(slope));
      return sqrt(w3.divideDecimal(expiryData.tAnnualized)).divideDecimal(expiryData.baseIv);
  }

  /** 
   * @notice Array version of getSkewForStrike(), returns skews for strikeTargets as is if they already
   *         exist, or interpolates between existing strikes if the target does not exist.
   * @param expiryData The "live" volatility slice in the form of ExpiryData.
   * @param strikeTargets The new strike for which skew is reqeusted (in $ form, 18 decimals).
   * @param revertIfAlreadyExists A flag to revert the tx if strikeTarget already exists in expiryData.
   * @return skews New strikes' skews.
   */
  function _getSkewForStrikeArray(
    ExpiryData memory expiryData,
    uint[] memory strikeTargets,
    bool revertIfAlreadyExists
  ) internal view returns (uint[] memory skews) {
    // TODO check if sorted and ignore? Or add a flag to the ExpiryData struct? Maybe assume it's sorted?
    _sortStrike(expiryData.strikes);
    skews = new uint[](strikeTargets.length);
    for (uint i; i<strikeTargets.length; i++) {
      skews[i] = getSkewForStrike(expiryData, strikeTargets[i], revertIfAlreadyExists);
    }
  }

  /** 
   * @notice Interpolates baseIv and an array of skews for a new expiry.
   * @param expiryArray The "live" volatility slice in the form of ExpiryData.
   * @param idx The index of expiryArray, such that (expiryArray[idx-1] < tTarget <= expiryArray[idx])
   * @param tTarget The annualized time-to-expiry of the new surface user wants to generate.
   * @param strikeTargets The strikes for the new surface user wants to generate (in $ form, 18 decimals).
   * @param spot Current chainlink spot price.
   * @param forceATMSkew Value for ATM skew to anchor towards, e.g. 1e18 will ensure ATM skew is set to 1.0.
   * @return baseIv BaseIV for the new board.
   * @return skews Array of skews for each strike in strikeTargets.
   */
  function _interpolateExpiry(
    ExpiryData[] memory expiryArray,
    uint idx,
    uint tTarget,
    uint[] memory strikeTargets,
    uint spot,
    uint forceATMSkew
  ) internal view returns (uint baseIv, uint[] memory skews) {
    uint[] memory volsMid = _interpolateVols(expiryArray, idx, tTarget, strikeTargets);
    uint[] memory strikeSpotDistances = new uint[](strikeTargets.length);
    for (uint i=0; i<strikeSpotDistances.length; i++) {
      strikeSpotDistances[i] = Math.abs(int(strikeTargets[i]) - int(spot));
    }
    // TODO simplification candidate: stick to a convention that ATM strike = first K s.t. S > K?
    // will allow dropping strikeSpotDistances and allow us to remove argmin func (can use search sorted instead)
    // only do this if the Katm is simplifed to be the left point (to be consistent)
    // if doing this, change extrapolate logic to avoid strikeSpotDistances as well
    uint argMinIdx = _argMin(strikeSpotDistances);
    baseIv = volsMid[argMinIdx].divideDecimal(forceATMSkew);
    // convert the vols array to skews array now that baseIv is known
    for (uint i=0; i<volsMid.length; i++){
      volsMid[i] = volsMid[i].divideDecimal(baseIv);
    }
    return (baseIv, volsMid);
  }

  /** 
   * @notice Interpolates the vol points (i.e. before splitting them into baseIv and skew components)
   * @param expiryArray The "live" volatility slice in the form of ExpiryData.
   * @param idx The index of expiryArray, such that (expiryArray[idx-1] < tTarget <= expiryArray[idx])
   * @param tTarget The annualized time-to-expiry of the new surface user wants to generate.
   * @param strikeTargets The strikes for the new surface user wants to generate (in $ form, 18 decimals).
   * @return volsMid Interpolated volatilities.
   */
  function _interpolateVols(
    ExpiryData[] memory expiryArray,
    uint idx,
    uint tTarget,
    uint[] memory strikeTargets
    ) internal view returns (uint[] memory) {
    uint[] memory volsMid = new uint[](strikeTargets.length);
    ExpiryData memory expiryDataLeft = expiryArray[idx-1];
    ExpiryData memory expiryDataRight = expiryArray[idx];
    uint yLeft = (expiryDataRight.tAnnualized - tTarget).divideDecimal(
      expiryDataRight.tAnnualized - expiryDataLeft.tAnnualized);
    uint[] memory skewsLeft = _getSkewForStrikeArray(expiryDataLeft, strikeTargets, false);
    uint[] memory skewsRight = _getSkewForStrikeArray(expiryDataRight, strikeTargets, false);

    for (uint i=0; i<volsMid.length; i++) {
      uint wLeft = skewsLeft[i].multiplyDecimal(expiryDataLeft.baseIv);
      wLeft = wLeft.multiplyDecimal(wLeft).multiplyDecimal(expiryDataLeft.tAnnualized);
      uint wRight = skewsRight[i].multiplyDecimal(expiryDataRight.baseIv);
      wRight = wRight.multiplyDecimal(wRight).multiplyDecimal(expiryDataRight.tAnnualized);
      volsMid[i] = sqrt(
        (yLeft.multiplyDecimal(wLeft) +
         (UNIT - yLeft).multiplyDecimal(wRight)
        ).divideDecimal(tTarget));
    }
    return volsMid;
  }

  /** 
   * @notice Extrapolate baseIv and an array of skews for a new expiry.
   * @param expiryArray The "live" volatility slice in the form of ExpiryData.
   * @param idx The index of expiryArray's edge, i.e. 0 or expiryArray.length - 1 
   * @param tTarget The annualized time-to-expiry of the new surface user wants to generate.
   * @param strikeTargets The strikes for the new surface user wants to generate (in $ form, 18 decimals).
   * @param spot Current chainlink spot price.
   * @param forceATMSkew Value for ATM skew to anchor towards, e.g. 1e18 will ensure ATM skew is set to 1.0.
   * @return baseIv BaseIV for the new board.
   * @return skews Array of skews for each strike in strikeTargets.
   */
  function _extrapolateExpiry(
    ExpiryData[] memory expiryArray,
    uint idx,
    uint tTarget,
    uint[] memory strikeTargets,
    uint spot,
    uint forceATMSkew
  ) internal view returns (uint baseIv, uint[] memory skews) {
    ExpiryData memory expiryData = expiryArray[idx];
    // assumption: sigma(z(T1), T1) == sigma(z(T2), T2)
    // i.e. vols are the same at the same standard moneyness points z
    // in other words, 80-delta option with 2m expiry has roughly same vol as an 3m 80-delta option
    // hence to get the extrapolated sigma(z(T2), T2), we need to map strikeTargets -> z(T2)
    // then recover strikesT1 from z(T1) = z(T2) by inverting z
    uint[] memory strikesT1 = new uint[](strikeTargets.length);
    uint[] memory strikeSpotDistances = new uint[](strikeTargets.length);
    for (uint i=0; i<strikesT1.length; i++){
      int moneyness = _strikeToMoneyness(strikeTargets[i], spot, tTarget);
      strikeSpotDistances[i] = Math.abs(int(strikeTargets[i]) - int(spot));
      strikesT1[i] = _moneynessToStrike(moneyness, spot, expiryData.tAnnualized);
    }
    uint[] memory expirySkews = _getSkewForStrikeArray(expiryData, strikesT1, false);
    // return the extrapolated values as is if there is no forceATMSkew
    // TODO rug this, no reason to support both 0 and non-zero imo forceATMSkew, let's pick one
    if (forceATMSkew == 0) return (expiryData.baseIv, expirySkews);
    // otherwise re-scale baseIv and skews to ensure ATM skew for new expiry == forceATMSkew (usually 1.0)
    uint argMinIdx = _argMin(strikeSpotDistances);
    uint scaler = forceATMSkew.divideDecimal(expirySkews[argMinIdx]);
    for (uint i=0; i<expirySkews.length; i++){
      expirySkews[i] = expirySkews[i].multiplyDecimal(scaler);
    }
    return (expiryData.baseIv.divideDecimal(scaler), expirySkews);
  }

  /**
   * @notice Searches for an index such that inserting target at that index preserves array order.
   * @dev this is equivalent in output & behaviour to numpy's `left` searchsorted
   *      https://numpy.org/doc/stable/reference/generated/numpy.searchsorted.html
   * @param values A sorted array of uint values.
   * @param target Target value to search.
   * @return idx Index in values array such that inserting target at that index would preserve sorting.
   */
  function _searchSorted(uint[] memory values, uint target) internal view returns (uint idx) { unchecked {
    if (target <= values[0]) return 0;
    if (target > values[values.length - 1]) return values.length;
    for (uint i=0; i < values.length - 1; i++) {
      if ((target > values[i]) && (target <= values[i+1])) return (i+1);
    }
    return values.length; // this should never happen since the above captures all cases
  }}

  /**
   * @notice Searches for an exact match of target in values[].
   * @param values An array of uint values.
   * @param target Target value to search.
   * @return idx Index of target in values[].
   */
  function _indexOf(uint[] memory values, uint target) internal view returns (uint idx) { unchecked {
    for (uint i=0; i < values.length; i++) {
      if (target == values[i]) return i;
    }
    return values.length;
  }}

  /**
   * @notice Searches for an exact match of target in values[], and returns true if exists.
   * @param values An array of uint values.
   * @param target Target value to search.
   * @return exists Bool, true if exists.
   */
  function _existsIn(uint[] memory values, uint target) internal view returns (bool exists) { unchecked {
    return (_indexOf(values, target) != values.length);
  }}

  /**
   * @notice Searches for an arg min of an array.
   * @param values An array of uint values.
   * @return idx Index of the smallest element.
   */
  function _argMin(uint[] memory values) internal view returns (uint idx) { unchecked {
    uint min = values[0];
    for (uint i=1; i < values.length; i++) {
      if (values[i] < min) {
        idx = i;
        min = values[i];
      }
    }
  }}

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
  function _quickSortExpiry(ExpiryData[] memory data, uint low, uint high) internal view { unchecked {
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
  }}

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
  function _quickSortStrike(StrikeData[] memory data, uint low, uint high) internal view { unchecked {
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
  }}

  /**
   * TODO Should we update FixedPointMathLib to a version that has sqrt?
   * @notice Returns the square root of a value using Newton's method.
   */
  function sqrt(uint x) internal view returns (uint) {
    // Add in an extra unit factor for the square root to gobble;
    // otherwise, sqrt(x * UNIT) = sqrt(x) * sqrt(UNIT)
    return BlackScholes._sqrt(x * UNIT);
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
  function _strikeToMoneyness(
    uint strike,
    uint spot,
    uint tAnnualized
  ) internal view returns (int moneyness) { unchecked {
    moneyness = int(strike.divideDecimal(spot)).ln().divideDecimal(int(sqrt(tAnnualized)));
  }}

  /**
   * @notice Converts standard moneyness back to a $ strike.
   * @dev Literally "undoes" _strikeToMoneyness()
   * @param moneyness moneyness as defined in _strikeToMoneyness()
   * @param spot dollar Chainlink spot, 18 decimals
   * @param tAnnualized annualized time-to-expiry, 18 decimals
   */  
  function _moneynessToStrike(
    int moneyness,
    uint spot,
    uint tAnnualized
  ) internal view returns (uint strike) { unchecked {
    strike = moneyness.multiplyDecimal(int(sqrt(tAnnualized))).exp().multiplyDecimal(spot);
  }}

  /**
   * @notice Returns n'th element of the strike pivot schema.
   * @dev Returns n'th element of the sequence from the 0'th element p0=1:
   *      [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000,
   *       100000, 200000, 500000, 1000000, 2000000, 5000000, 10000000, 20000000, 50000000,...].
   *      Uses 300 gas.
   *      Can maybe be changed to a hardcoded table lookup once we agree we like these pivots.
   * @param n which element to compute by index
   * @return pn the n'th element of the sequence
   */  
  function _nthPivot(uint n) internal view returns (uint pn) { unchecked {
    if (n > MAX_PIVOT_INDEX + 1) revert PivotIndexAboveMax(n);
    uint extraPow2 = (n % 3 == 1) ? uint(1) : uint(0);
    uint extraPow5 = (n % 3 == 2) ? uint(1) : uint(0);
    pn = 2**(n/3 + extraPow2) * 5**(n/3 + extraPow5);
  }}

  /**
   * @notice Returns the strike step corresponding to the pivot bucket and the time-to-expiry.
   * @dev Since vol is approx ~ sqrt(T), it makes sense to double the step size
   *      every time tAnnualized is roughly quadripled
   * @param p The pivot strike.
   * @param tAnnualized Years to expiry, 18 decimals.
   * @return step The strike step size at this pivot and tAnnualized.
   */  
  function _strikeStep(uint p, uint tAnnualized) internal view returns (uint step) { unchecked {
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
  }} 

  /**
   * @notice Finds an ATM strike complying with our pivot/step schema.
   * @dev Consumes up to about 10k gas.
   * @param spot Spot price.
   * @param tAnnualized Years to expiry, 18 decimals.
   * @return strike The first strike satisfying strike <= spot < (strike + step).
   */ 
  function _findATMStrike(uint spot, uint tAnnualized) internal view returns (uint strike, uint step) { unchecked {
    uint n = _findSpotPivot(spot);
    strike = _nthPivot(n);
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
  }}

  /**
   * @notice Returns the index of the pivot bucket the spot belongs to (i.e. p(n) <= spot < p(n+1)).
   * @param spot Spot price.
   * @return n The index of the pivot bucket the spot belongs to.
   */  

   // todo [Josh]: change this to pass in for constructor
  function _findSpotPivot(uint spot) internal view returns (uint n) { unchecked {
    if (spot >= MAX_PIVOT) revert SpotPriceAboveMaxStrike(spot);
    if (spot == 0) revert SpotPriceIsZero(spot);
    uint a = 0;
    uint b = MAX_PIVOT_INDEX;
    n = (a + b) / 2; // initial guess for the bucket that spot belongs to
    while (true) {
      int8 spotDirection = _getSpotDirection(n, spot);
      if (spotDirection == int8(0)) {
        return n;
      }
      if (spotDirection == int8(1)) {
        a = n;
        n = (a + b) / 2;
      }
      else {
        b = n;
        n = (a + b) / 2;
      }
    }
  }}

  /**
   * @notice Returns whether the spot is between p(n) and p(n+1), below p(n), or above p(n+1)
   * @dev A helper for _findSpotPivot()._divideDecimalRound(y, precisionUnit);
   * @param spot Spot price.
   * @param n The pivot index to check.
   * @return direction 0 if p(n) <= spot < p(n+1), 1 if spot >= p(n+1), -1 if spot < p(n)
   */  
  function _getSpotDirection(uint n, uint spot) internal view returns (int8 direction) {
    uint p0 = _nthPivot(n);
    if (spot >= p0) {
      uint p1 = _nthPivot(n+1);
      if (spot < p1) return 0;
      else return 1;
    }
    else {
      return -1;
    }
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