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
    using DecimalMath for uint256;
    using SignedDecimalMath for int256;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;

    /// @dev For strike extrapolation, slope of totalVol(log-moneyness) is known to be bounded
    ///      by 2 from Roger-Lee formula for large enough strikes
    ///      we adopt this bound for all strike extrapolations to avoid unexpected overshooting
    int256 private constant MAX_STRIKE_EXTRAPOLATION_SLOPE = 2e18;
    uint256 private constant UNIT = 1e18;
    // when queriying nth element of the strike schema, n is capped at MAX_PIVOT_INDEX to avoid overflow
    uint256 private constant MAX_PIVOT_INDEX = 200;
    // value of the pivot at n = (MAX_PIVOT_INDEX+1), add 1 since we want the right point of the bucket
    uint256 private constant MAX_PIVOT = 10 ** 67;

    struct StrikeData {
        // strike price
        uint256 strikePrice;
        // volatility component specific to the strike listing (boardIv * skew = vol of strike)
        uint256 skew;
    }

    struct ExpiryData {
        // The annualized time when the board expires.
        uint256 tAnnualized;
        // The initial value for baseIv (baseIv * skew = strike volatility).
        uint256 baseIv;
        // An array of strikes (strike prices and skews) belonging to this expiry
        StrikeData[] strikes;
    }

    function createBoard(
        ExpiryData[] memory expiryArray,
        uint256 tTarget, // TODO write up expiry schema and force createBoard() to use that schema as opposed to tTarget?
        uint256 spot,
        uint256 maxScaledMoneyness,
        uint256 maxNumStrikes,
        uint256 forceATMSkew
    ) public view returns (uint256[] memory strikes) {
        // TODO uint tTarget = getSchemaExpiry(expiryArray,...)
        uint256[] memory liveStrikes = new uint[](0);
        strikes = getSchemaStrikes(tTarget, spot, maxScaledMoneyness, maxNumStrikes, liveStrikes);
    }

    function extendBoard(ExpiryData memory expiryData, uint256 spot, uint256 maxScaledMoneyness, uint256 maxNumStrikes)
        public
        view
        returns (uint256[] memory strikes)
    {
        uint256[] memory liveStrikes = new uint[](expiryData.strikes.length);
        for (uint256 i; i < expiryData.strikes.length; i++) {
            liveStrikes[i] = expiryData.strikes[i].strikePrice;
        }
        strikes = getSchemaStrikes(expiryData.tAnnualized, spot, maxScaledMoneyness, maxNumStrikes, liveStrikes);
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
        uint256 tTarget,
        uint256 spot,
        uint256 maxScaledMoneyness,
        uint256 maxNumStrikes,
        uint256[] memory liveStrikes
    ) public view returns (uint256[] memory strikes) {
        // todo [Josh]: should return new strikes, instead of total strikes? Or maybe both
        uint256 remainNumStrikes = maxNumStrikes > liveStrikes.length ? maxNumStrikes - liveStrikes.length : uint256(0);
        if (remainNumStrikes == 0) return new uint[](0);
        uint256 atmStrike;
        uint256 step;
        (atmStrike, step) = _findATMStrike(spot, tTarget);
        uint256 maxStrike;
        uint256 minStrike;
        {
            uint256 strikeScaler = int256(maxScaledMoneyness.multiplyDecimal(sqrt(tTarget))).exp();
            maxStrike = spot.multiplyDecimal(strikeScaler);
            minStrike = spot.divideDecimal(strikeScaler);
        }
        bool addAtm = (!_existsIn(liveStrikes, atmStrike));
        // remainNumStrikes == 0 is handled above, subbing 1 is safe
        remainNumStrikes -= (addAtm ? uint256(1) : uint256(0));
        uint256[] memory strikesLeft = new uint[](remainNumStrikes);
        uint256[] memory strikesRight = new uint[](remainNumStrikes);
        uint256 nLeft;
        uint256 nRight;
        // starting from ATM strike, go left and right in steps of step
        // record a new strike if it does not exist in liveStrikes and if it is within min/max bounds
        for (uint256 i = 0; i < remainNumStrikes; i++) {
            // todo [Josh]: can probably remove this if by formatting pivots differently
            uint256 newLeft = (atmStrike > (i + 1) * step) ? atmStrike - (i + 1) * step : uint256(0);
            uint256 newRight = atmStrike + (i + 1) * step;
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
        for (uint256 i = 0; i < strikesLeft.length; i++) {
            if (strikesLeft[i] != 0) {
                nLeft--;
                strikes[nLeft] = strikesLeft[i];
            }
        }
        for (uint256 i = 0; i < strikesRight.length; i++) {
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
    function _searchSorted(uint256[] memory values, uint256 target) internal view returns (uint256 idx) {
        unchecked {
            if (target <= values[0]) return 0;
            if (target > values[values.length - 1]) return values.length;
            for (uint256 i = 0; i < values.length - 1; i++) {
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
    function _indexOf(uint256[] memory values, uint256 target) internal view returns (uint256 idx) {
        unchecked {
            for (uint256 i = 0; i < values.length; i++) {
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
    function _existsIn(uint256[] memory values, uint256 target) internal view returns (bool exists) {
        unchecked {
            return (_indexOf(values, target) != values.length);
        }
    }

    /**
     * @notice Searches for an arg min of an array.
     * @param values An array of uint values.
     * @return idx Index of the smallest element.
     */
    function _argMin(uint256[] memory values) internal view returns (uint256 idx) {
        unchecked {
            uint256 min = values[0];
            for (uint256 i = 1; i < values.length; i++) {
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
    function _quickSortExpiry(ExpiryData[] memory data, uint256 low, uint256 high) internal view {
        unchecked {
            if (low < high) {
                uint256 pivotVal = data[(low + high) / 2].tAnnualized;

                uint256 low1 = low;
                uint256 high1 = high;
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
    function _quickSortStrike(StrikeData[] memory data, uint256 low, uint256 high) internal view {
        unchecked {
            if (low < high) {
                uint256 pivotVal = data[(low + high) / 2].strikePrice;

                uint256 low1 = low;
                uint256 high1 = high;
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
     * TODO Should we update FixedPointMathLib to a version that has sqrt?
     * @notice Returns the square root of a value using Newton's method.
     */
    function sqrt(uint256 x) internal view returns (uint256) {
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
    function _strikeToMoneyness(uint256 strike, uint256 spot, uint256 tAnnualized)
        internal
        view
        returns (int256 moneyness)
    {
        unchecked {
            moneyness = int256(strike.divideDecimal(spot)).ln().divideDecimal(int256(sqrt(tAnnualized)));
        }
    }

    /**
     * @notice Converts standard moneyness back to a $ strike.
     * @dev Literally "undoes" _strikeToMoneyness()
     * @param moneyness moneyness as defined in _strikeToMoneyness()
     * @param spot dollar Chainlink spot, 18 decimals
     * @param tAnnualized annualized time-to-expiry, 18 decimals
     */
    function _moneynessToStrike(int256 moneyness, uint256 spot, uint256 tAnnualized)
        internal
        view
        returns (uint256 strike)
    {
        unchecked {
            strike = moneyness.multiplyDecimal(int256(sqrt(tAnnualized))).exp().multiplyDecimal(spot);
        }
    }

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
    function _nthPivot(uint256 n) internal view returns (uint256 pn) {
        unchecked {
            if (n > MAX_PIVOT_INDEX + 1) revert PivotIndexAboveMax(n);
            uint256 extraPow2 = (n % 3 == 1) ? uint256(1) : uint256(0);
            uint256 extraPow5 = (n % 3 == 2) ? uint256(1) : uint256(0);
            pn = 2 ** (n / 3 + extraPow2) * 5 ** (n / 3 + extraPow5);
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
    function _strikeStep(uint256 p, uint256 tAnnualized) internal view returns (uint256 step) {
        unchecked {
            // TODO make these magic numbers into params, e.g. struct/duoble array as input?
            uint256 div;
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
    function _findATMStrike(uint256 spot, uint256 tAnnualized) internal view returns (uint256 strike, uint256 step) {
        unchecked {
            uint256 n = _findSpotPivot(spot);
            strike = _nthPivot(n);
            step = _strikeStep(strike, tAnnualized);
            while (true) {
                // by construction, we start with strike <= spot
                // return the first strike such that strike <= spot < (strike + step)
                // round to the closest between strike and (strike + step)
                // TODO simplification candidate - can have a convention to round to left
                // but then probably change the left/right fill priority to be right (currently left is added first)
                if (spot < strike + step) {
                    uint256 distanceLeft = spot - strike;
                    uint256 distanceRight = (strike + step) - spot;
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

    // todo [Josh]: change this to pass in for constructor
    function _findSpotPivot(uint256 spot) internal view returns (uint256 n) {
        unchecked {
            if (spot >= MAX_PIVOT) revert SpotPriceAboveMaxStrike(spot);
            if (spot == 0) revert SpotPriceIsZero(spot);
            uint256 a = 0;
            uint256 b = MAX_PIVOT_INDEX;
            n = (a + b) / 2; // initial guess for the bucket that spot belongs to
            while (true) {
                int8 spotDirection = _getSpotDirection(n, spot);
                if (spotDirection == int8(0)) {
                    return n;
                }
                if (spotDirection == int8(1)) {
                    a = n;
                    n = (a + b) / 2;
                } else {
                    b = n;
                    n = (a + b) / 2;
                }
            }
        }
    }

    /**
     * @notice Returns whether the spot is between p(n) and p(n+1), below p(n), or above p(n+1)
     * @dev A helper for _findSpotPivot()._divideDecimalRound(y, precisionUnit);
     * @param spot Spot price.
     * @param n The pivot index to check.
     * @return direction 0 if p(n) <= spot < p(n+1), 1 if spot >= p(n+1), -1 if spot < p(n)
     */
    function _getSpotDirection(uint256 n, uint256 spot) internal view returns (int8 direction) {
        uint256 p0 = _nthPivot(n);
        if (spot >= p0) {
            uint256 p1 = _nthPivot(n + 1);
            if (spot < p1) return 0;
            else return 1;
        } else {
            return -1;
        }
    }

    ////////////
    // Errors //
    ////////////
    error EmptyStrikes();
    error EmptyExpiries();

    error StrikeAlreadyExists(uint256 newStrike);
    error ExpiryAlreadyExists(uint256 newExpiry);

    error ZeroATMSkewNotAllowed();

    error PivotIndexAboveMax(uint256 n);
    error SpotPriceAboveMaxStrike(uint256 spot);
    error SpotPriceIsZero(uint256 spot);
}
