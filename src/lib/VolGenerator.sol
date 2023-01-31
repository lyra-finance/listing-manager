//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "openzeppelin/utils/math/SafeCast.sol";
import "newport/synthetix/DecimalMath.sol";

// todo: maybe use the new Black76 and FixedPointMathLib and get those audited
import "newport/libraries/FixedPointMathLib.sol";
import "newport/libraries/BlackScholes.sol";
import "newport/libraries/Math.sol";
import "lyra-utils/arrays/UnorderedMemoryArray.sol";

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
  using SafeCast for int;
	using UnorderedMemoryArray for uint[];

	///////////////
	// Constants //
	///////////////

  /// @dev For strike extrapolation, slope of totalVol(log-moneyness) is known to be bounded
  ///      by 2 from Roger-Lee formula for large enough strikes
  ///      we adopt this bound for all strike extrapolations to avoid unexpected overshooting
  int private constant MAX_STRIKE_EXTRAPOLATION_SLOPE = 2e18;

	//////////////////
	// Within Board //
	//////////////////

	function interpolateOrExtrapolateWithinBoard(
		uint newStrike,
		uint[] orderedLiveStrikePrices,
		uint[] orderedLiveSkews,
		uint baseIv,
		uint tAnnualized
	) public pure returns (uint newSkew) {
		if (expiryData.strikes.length == 0) {
			revert VG_NoStrikes();
		}

		// if only 1 strike, cannot interpolate or extrapolate
    if (expiryData.strikes.length == 1) {
			return orderedLiveSkews[0];
		}

    // early return if found match
		// todo: can use binary search here but need to add memory binary search to lyra-utils
		int index = orderedLiveStrikePrices.findInArray(newStrike, orderedLiveStrikePrices.length);
		if (index >= 0) {
			return orderedLiveSkews[uint(index)];
		}

    // if failed, interpolate / extrapolate
    // ASSUME expiryData is already sorted!!!

		// todo: should combine with above and just use binary search.
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
   * @notice Interpolates skew for a new strike when given adjacent strikes.
   * @param newStrike The strike for which skew will be interpolated.
   * @param leftStrike Must be less than midStrike.
   * @param rightStrike Must be greater than midStrike.
	 * @param leftSkew The skew of leftStrike.
   * @param rightSkew The skew of rightStrike
	 * @param baseIv The base volatility of the board
   * @return newSkew New strike's skew.
   */
	function interpolateSkewWithinBoard(
		uint newStrike,
		uint leftStrike,
		uint rightStrike,
		uint leftSkew,
		uint rightSkew,
		uint baseIv
  ) public pure returns (uint newSkew) {
		// ensure mid strike is actually in the middle
		if (!(leftStrike < newStrike && newStrike < rightStrike)) {
			revert VG_ImproperStrikeOrderDuringInterpolation(leftStrike, newStrike, rightStrike);
		}

		// get left and right variances
		uint varianceLeft = getVariance(baseIv, leftSkew);
		uint varianceRight = getVariance(baseIv, rightSkew);

		// convert strikes into ln space
		int lnMStrike = int(newStrike).ln();
		int lnLStrike = int(leftStrike).ln();
		int lnRStrike = int(rightStrike).ln();

		// interpolate
		uint ratio = SafeCast.toUint256((lnRStrike - lnMStrike).divideDecimal(lnRStrike - lnLStrike));

		uint vol = sqrtWeightedAvg(ratio, varianceLeft, varianceRight, 1e18);
		return vol.divideDecimal(baseIv);
  }

	/**
   * @notice Extrapolates a skew for a new strike from a "live" vol slice.
   * @param newStrike The strike for which skew is found.
   * @param edgeStrike The outermost strike that is nearest to the newStrike.
   * @param insideStrike The strike adjacent to the edgeStrike, so that abs(newStrike) > abs(edgeStrike) > abs(insideStrike)
   * @param edgeSkew The skew of the edgeStrike.
   * @param insideSkew The skew of the insideStrike
	 * @param baseIv The base volatility of the board
   * @param tAnnualized The annualized time to expiry.
	 * @return newSkew New strike's skew.
   */
  function extrapolateSkewWithinBoard(
    uint newStrike,
    uint edgeStrike,
		uint insideStrike,
		uint edgeSkew,
		uint insideSkew,
		uint baseIv,
		uint tAnnualized
  ) public pure returns (uint newSkew) {
		// ensure strikes are properly ordered
		if (!(newStrike < edgeStrike && edgeStrike < insideStrike) &&
			!(insideStrike < edgeStrike && edgeStrike < newStrike)) {
			revert VG_ImproperStrikeOrderDuringExtrapolation(insideStrike, edgeStrike, newStrike);
		}

		// convert strikes into ln space
		int lnNewStrike = int(newStrike).ln();
		int lnEdgeStrike = int(edgeStrike).ln();
		int lnInsideStrike = int(insideStrike).ln();

		// get variances
		uint edgeVariance = getVariance(baseIv, edgeSkew).multiplyDecimal(tAnnualized);
		uint insideVariance = getVariance(baseIv, insideSkew).multiplyDecimal(tAnnualized);

		// get capped slope
		int slope = (int(edgeVariance)-int(insideVariance)).divideDecimal(int(Math.abs(lnEdgeStrike-lnInsideStrike)));
		if (slope < 0) {
			slope = int(0);
		} else if (slope > MAX_STRIKE_EXTRAPOLATION_SLOPE) {
			slope = MAX_STRIKE_EXTRAPOLATION_SLOPE;
		}

		// extrapolate new skew
		uint newVariance = edgeVariance + Math.abs(lnNewStrike-lnEdgeStrike).multiplyDecimal(uint(slope));
		return BlackScholes._sqrt(newVariance.divideDecimal(tAnnualized) * DecimalMath.UNIT).divideDecimal(baseIv);
  }

	///////////////////
	// Across Boards //
	///////////////////

	/**
   * @notice Interpolates skew for a new baord using exact strikes from longer/shorted dated boards.
   * @param leftSkew Skew from same strike but shorter dated board.
   * @param rightSkew Skew from same strike but longer dated board.
   * @param leftBaseIv BaseIv of the shorter dated board.
   * @param rightBaseIv BaseIv of the longer dated board.
   * @param leftT Annualized time to expiry of the shorter dated board.
	 * @param rightT Annualized time to expiry of the longer dated board.
   * @param tTarget Annualied time to expiry of the targer strike
   * @param baseIv BaseIv of the board with the new strike
	 * @return newSkew New strike's skew.
   */
	function interpolateSkewAcrossBoards(
    uint leftSkew,
		uint rightSkew,
		uint leftBaseIv,
		uint rightBaseIv,
		uint leftT,
		uint rightT,
    uint tTarget,
		uint baseIv
) public pure returns (uint newSkew) {
		if (!(leftT < tTarget && tTarget < rightT)) {
			revert VG_ImproperExpiryOrderDuringInterpolation(leftT, tTarget, rightT);
		}

    uint ratio = (rightT - tTarget).divideDecimal(rightT - leftT);

		// convert to variance
		uint leftVariance = getVariance(leftBaseIv, leftSkew).multiplyDecimal(leftT);
		uint rightVariance = getVariance(rightBaseIv, rightSkew).multiplyDecimal(rightT);

		// interpolate
		uint vol = sqrtWeightedAvg(ratio, leftVariance, rightVariance, tTarget);
		return vol.divideDecimal(baseIv);
  }

	/**
   * @notice Extrapolates skew for a strike on a new board.
	 *			   Assumes: sigma(z(T1), T1) == sigma(z(T2), T2)
   *				 i.e. "2mo 80-delta option" has same vol as "3mo 80-delta option".
   * @param newStrike The "live" volatility slice in the form of ExpiryData.
   * @param edgeBoardT The index of expiryArray's edge, i.e. 0 or expiryArray.length - 1
   * @param tTarget The annualized time-to-expiry of the new surface user wants to generate.
   * @param spot Current chainlink spot price.
   * @param baseIv Value for ATM skew to anchor towards, e.g. 1e18 will ensure ATM skew is set to 1.0.
   * @return newSkew Array of skews for each strike in strikeTargets.
   */
  function extrapolateSkewAcrossBoards(
    uint newStrike,
    uint edgeBoardT,
    uint tTarget,
    uint spot,
    uint baseIv
  ) internal view returns (uint newSkew) {
    ExpiryData memory expiryData = expiryArray[idx];
    // map newStrike to a strike on the edge board with the same moneyness
		int moneyness = strikeToMoneyness(newStrike, spot, tTarget);
		uint strikeOnEdgeBoard = moneynessToStrike(moneyness, spot, edgeBoardT);

    return interpolateOrExtrapolateWithinBoard();
  }

	/////////////
	// Helpers //
	/////////////

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
  function strikeToMoneyness(
    uint strike,
    uint spot,
    uint tAnnualized
  ) public pure returns (int moneyness) { unchecked {
    moneyness = int(strike.divideDecimal(spot)).ln().divideDecimal(
			int(BlackScholes._sqrt(tAnnualized * DecimalMath.UNIT))
		);
  }}

  /**
   * @notice Converts standard moneyness back to a $ strike.
   * 				 Inverse of `strikeToMoneyness()`.
   * @param moneyness moneyness as defined in _strikeToMoneyness()
   * @param spot dollar Chainlink spot, 18 decimals
   * @param tAnnualized annualized time-to-expiry, 18 decimals
   */
  function moneynessToStrike(
    int moneyness,
    uint spot,
    uint tAnnualized
  ) internal view returns (uint strike) { unchecked {
    strike = moneyness.multiplyDecimal(int(sqrt(tAnnualized))).exp().multiplyDecimal(spot);
  }}

	/**
   * @notice Calculates variance given the baseIv and skew.
   * @param baseIv The base volatility of the board.
   * @param skew The volatility skew of the given strike.
	 * @return variance Variance of the given strike.
   */
	function getVariance(uint baseIv, uint skew) public pure returns (uint variance) {
		// todo: good candidate for a standalone Lyra-util library
		variance = baseIv.multiplyDecimal(skew);
		return variance.multiplyDecimal(variance);
	}

	function sqrtWeightedAvg(
		uint leftVal,
		uint leftWeight,
		uint rightWeight,
		uint denominator
	) public pure returns (uint) {

		uint weightedAvg = leftVal.multiplyDecimal(leftWeight) +
			(DecimalMath.UNIT - leftVal).multiplyDecimal(rightWeight);

    return BlackScholes._sqrt(weightedAvg.divideDecimal(denominator) * DecimalMath.UNIT);
	}

	////////////
	// Errors //
	////////////

	error VG_ImproperStrikeOrderDuringInterpolation(uint leftStrike, uint midStrike, uint rightStrike);
	error VG_ImproperStrikeOrderDuringExtrapolation(uint insideStrike, uint edgeStrike, uint newStrike);
	error VG_ImproperExpiryOrderDuringInterpolation(uint leftT, uint tTarget, uint rightT);
}
