//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "openzeppelin/utils/math/SafeCast.sol";
import "newport/synthetix/DecimalMath.sol";

// todo: maybe use the new Black76 and FixedPointMathLib and get those audited
import "newport/libraries/FixedPointMathLib.sol";
import "newport/libraries/BlackScholes.sol";
import "newport/libraries/Math.sol";
import "lyra-utils/arrays/MemoryBinarySearch.sol";

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
	using MemoryBinarySearch for uint[];

	struct Board {
		uint tAnnualized;
		uint baseIv;
		uint[] orderedStrikePrices;
		uint[] orderedSkews;
	}

	// ////////////////////
	// // Board Indexing //
	// ////////////////////

	// /**
	//  * @notice Returns the first index that has an expiry greater or equal to `tTarget`
	//  *			   Will return orderedTs.length if `tTarget` greater than all values in array.
	//  * @param tTarget Target board expiry to find for
	//  * @param orderedTs Ordered list of board timeToExpiries (can be annualized) in ascending order
	//  * @return upperBoundIdx Returns the closest index of the tAnnualized that is greater than or equal to `tTarget`
	//  */
	// function findBoardIndex(
	// 	uint tTarget,
	// 	uint[] memory orderedTs
	// ) public pure returns (uint upperBoundIdx) {
	// 	return orderedTs.findUpperBound(tTarget);
	// }

	////////////////
	// End to End //
	////////////////

	function getNewSkewForNewBoard( // vs getNewSkewForNewBoard
		Board[] memory orderedBoards; // can simplify down to just left and right
		uint newStrike,
		uint tTarget,
		uint baseIv
	) public pure {
		// todo: need to think from perspective of when across vs within boards is used
		// these two are usually quite separate
	}

	function getNewSkewForExistingBoard(
		uint newStrike,
		uint[] orderedLiveStrikePrices,
		uint[] orderedLiveSkews,
		uint baseIv,
		uint tAnnualized
	) public pure returns (uint newSkew) {
		uint numLiveStrikes = orderedLiveStrikePrices.length;
		if (numLiveStrikes == 0) {
			revert VG_NoStrikes();
		}

    // early return if found exact match
		uint idx = orderedLiveStrikePrices.findUpperBound(newStrike);
		if (orderedLiveStrikePrices[idx] == newStrike) {
			return orderedLiveSkews[idx];
		}

		// determine whether to interpolate or extrapolate
    if (idx == 0) {
			return orderedLiveSkews[0];
    } else if (idx == numLiveStrikes) {
			return orderedLiveSkews[numLiveStrikes-1];
    } else {
			return interpolateSkewWithinBoard(
				newStrike,
				orderedLiveStrikePrices[idx - 1],
				orderedLiveStrikePrices[idx],
				orderedLiveSkews[idx - 1],
				orderedLiveSkews[idx],
				baseIv
			);
		}
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
		uint[] memory orderedEdgeBoardStrikes,
		uint[] memory orderedEdgeBoardSkews,
    uint edgeBoardT,
    uint tTarget,
    uint spot,
    uint baseIv
  ) internal view returns (uint newSkew) {
    // map newStrike to a strike on the edge board with the same moneyness
		int moneyness = strikeToMoneyness(newStrike, spot, tTarget);
		uint strikeOnEdgeBoard = moneynessToStrike(moneyness, spot, edgeBoardT);

    return getNewSkewForExistingBoard(
			newStrike,
			orderedEdgeBoardStrikes,
			orderedEdgeBoardSkews,
			baseIv, // todo [Josh]: is this the same baseIv for edge board and for new?
			tTarget
		);
  }


	//////////////////
	// Within Board //
	//////////////////

	function interpolateOrExtrapolateSkewWithinBoard(
		uint newStrike,
		uint[] orderedLiveStrikePrices,
		uint[] orderedLiveSkews,
		uint baseIv,
		uint tAnnualized
	) public pure returns (uint newSkew) {
		uint numLiveStrikes = orderedLiveStrikePrices.length;
		if (numLiveStrikes == 0) {
			revert VG_NoStrikes();
		}

    // early return if found exact match
		uint idx = orderedLiveStrikePrices.findUpperBound(newStrike);
		if (orderedLiveStrikePrices[idx] == newStrike) {
			return orderedLiveSkews[idx];
		}

		// determine whether to interpolate or extrapolate
    if (idx == 0) {
			return orderedLiveSkews[0];
    } else if (idx == numLiveStrikes) {
			return orderedLiveSkews[numLiveStrikes-1];
    } else {
			return interpolateSkewWithinBoard(
				newStrike,
				orderedLiveStrikePrices[idx - 1],
				orderedLiveStrikePrices[idx],
				orderedLiveSkews[idx - 1],
				orderedLiveSkews[idx],
				baseIv
			);
		}
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

	error VG_NoStrikes();
}
