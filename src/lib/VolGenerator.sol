//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "newport/synthetix/DecimalMath.sol";
import "newport/libraries/FixedPointMathLib.sol";
import "newport/libraries/BlackScholes.sol";

/**
 * @title Automated vol generator
 * @author Lyra
 * @notice The library automatically generates baseIv and skews for
 *         various input strikes. It uses other boards or existing strikes
 *         to best approximate an initial baseIv or skew for each new strike.
 */
library VolGenerator {
	using DecimalMath for uint;
  using SignedDecimalMath for int;
  using FixedPointMathLib for int;

  // /** 
  //  * @notice Generates baseIv and an array of skews for a new expiry.
  //  * @param expiryArray The "live" volatility surface in the form of ExpiryData[].
  //  * @param tTarget The annualized time-to-expiry of the new surface user wants to generate.
  //  * @param strikeTargets The strikes for the new surface user wants to generate (in $ form, 18 decimals).
  //  * @param spot Current chainlink spot price.
  //  * @param forceATMSkew Value for ATM skew to anchor towards, e.g. 1e18 will ensure ATM skew is set to 1.0.
  //  * @return baseIv BaseIV for the new board.
  //  * @return skews Array of skews for each strike in strikeTargets.
  //  */
  // function getVolsForExpiry(
  //   ExpiryData[] memory expiryArray,
  //   uint tTarget,
  //   uint[] memory strikeTargets,
  //   uint spot,
  //   uint forceATMSkew // TODO Can we assume strikeTargets always contains "ATM-ish" strike?
  // ) public view returns (uint baseIv, uint[] memory skews) {

  //   if (expiryArray.length == 0) revert EmptyExpiries();
  //   if (forceATMSkew == 0) revert ZeroATMSkewNotAllowed();

  //   // TODO can we assume the expiries are already fully sorted? Going to depend on the process of mapping
  //   // boards from storage to memory.
  //   _sortExpiry(expiryArray);
  //   uint idx;
  //   {
  //     uint[] memory tValues = new uint[](expiryArray.length);
  //     for (uint i; i < expiryArray.length; i++) {
  //       tValues[i] = expiryArray[i].tAnnualized;
  //     }
  //     // try to find exact match and revert if found
  //     idx = _indexOf(tValues, tTarget);
  //     if (idx != tValues.length) revert ExpiryAlreadyExists(tTarget);
  //     idx = _searchSorted(tValues, tTarget);
  //   }
  //   if (idx == 0) {
  //     return _extrapolateExpiry(expiryArray, 0, tTarget, strikeTargets, spot, forceATMSkew);
  //   }
  //   if (idx == expiryArray.length) {
  //     return _extrapolateExpiry(expiryArray, idx-1, tTarget, strikeTargets, spot, forceATMSkew);
  //   }
  //   return _interpolateExpiry(expiryArray, idx, tTarget, strikeTargets, spot, forceATMSkew);
  // }

	///////////////////////////////////
	// Interpolation & Extrapolation //
	///////////////////////////////////

  /** 
   * @notice Interpolates skew for a new strike when given adjacent strikes.
   * @param midStrike The strike for which skew will be interpolated.
   * @param leftStrike Must be less than midStrike.
   * @param rightStrike Must be greater than midStrike.
	 * @param leftSkew The skew of leftStrike.
   * @param rightSkew The skew of rightStrike
   * @param baseIv The board's baseIv.
   * @return midSkew New strike's skew.
   */
	function _interpolateStrike(
		uint midStrike,
		uint leftStrike,
		uint rightStrike,
		uint leftSkew,
		uint rightSkew,
		uint baseIv
  ) internal view returns (uint midSkew) {
		// ensure mid strike is actually in the middle
		if (midStrike < leftStrike || midStrike > rightStrike) {
			VG_StrikeNotInTheMiddle(leftStrike, midStrike, rightStrike);
		}

		// get left and right variances
		uint varianceLeft = baseIv.multiplyDecimal(leftStrike);
		varianceLeft = varianceLeft.multiplyDecimal(varianceLeft);

		uint varianceRight = baseIv.multiplyDecimal(rightSkew);
		varianceRight = varianceRight.multiplyDecimal(varianceRight);

		// convert strikes into ln space
		int lnMStrike = int(midStrike).ln();
		int lnLStrike = int(leftStrike).ln();
		int lnRStrike = int(rightStrike).ln();

		// linear interpolation of variance
		uint ratio = (lnRStrike - lnMStrike).divideDecimal(lnRStrike - lnLStrike);
		uint avgVariance = ratio.multiplyDecimal(varianceLeft)
			+ (SignedDecimalMath.UNIT - ratio).multiplyDecimal(varianceRight);
		
		return BlackScholes._sqrt(avgVariance * DecimalMath.UNIT).divideDecimal(baseIv);
  }

	// /** 
  //  * @notice Extrapolates a skew for a new strike from a "live" vol slice.
  //  * @param expiryData The "live" volatility slice in the form of ExpiryData.
  //  * @param idx The index of the edge of expiryData.strikes[], either 0 or expiryData.strikes.length - 1
  //  * @param newStrike The new strike for which skew is reqeusted (in $ form, 18 decimals).
  //  * @return newSkew New strike's skew.
  //  */
  // function _extrapolateStrike(
  //   ExpiryData memory expiryData,
  //   uint idx,
  //   uint newStrike
  // ) internal view returns (uint newSkew) {
  //     int slope;
  //     // total variance and log-strike of the "edge" (leftmost or rightmost) 
  //     uint w2 = expiryData.baseIv.multiplyDecimal(expiryData.strikes[idx].skew);
  //     w2 = w2.multiplyDecimal(w2).multiplyDecimal(expiryData.tAnnualized);
  //     int k2 = int(expiryData.strikes[idx].strikePrice).ln();
  //     {
  //       // block this out to resolve "stack too deep", we don't need w1 and k1 after slope is known
  //       // TODO do we need to handle k2 == k1? Should never happen but what if
  //       // total variance and log-strike of the second last element with respect to the edge
  //       // TODO also maybe rename the 1,2,3 convention lol
  //       uint idx1 = (idx == 0) ? 1 : idx - 1;
  //       uint w1 = expiryData.baseIv.multiplyDecimal(expiryData.strikes[idx1].skew);
  //       w1 = w1.multiplyDecimal(w1).multiplyDecimal(expiryData.tAnnualized);
  //       int k1 = int(expiryData.strikes[idx1].strikePrice).ln();
  //       slope = (int(w2)-int(w1)).divideDecimal(int(Math.abs(k2-k1)));
  //       // By construction, slope is expected to be positive (vol increaes in the tails), hence floor at 0
  //       // In absolute terms, slope is capped at MAX_STRIKE_EXTRAPOLATION_SLOPE
  //       /// TODO a rug candidate -> can think if we can just flat-extrapolate strikes
  //       /// (not gonna expect much of an error in 10-90 delta range)
  //       /// then no need to compute slope, have 2 strikes, etc.
  //       /// traders mostly short tails anyway, AMM doesn't want to be a buyer (?)
  //       slope = (slope > 0) ? slope : int(0);
  //       slope = (slope > MAX_STRIKE_EXTRAPOLATION_SLOPE) ? MAX_STRIKE_EXTRAPOLATION_SLOPE : slope;
  //     }
  //     int k3 = int(newStrike).ln();
  //     uint w3 = w2 + Math.abs(k3-k2).multiplyDecimal(uint(slope));
  //     return sqrt(w3.divideDecimal(expiryData.tAnnualized)).divideDecimal(expiryData.baseIv);
  // }

	////////////
	// Errors //
	////////////

	error VG_StrikeNotInTheMiddle(uint leftStrike, uint midStrike, uint rightStrike);

}