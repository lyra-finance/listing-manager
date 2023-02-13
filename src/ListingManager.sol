//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "../lib/openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import "../lib/lyra-protocol/contracts/synthetix/DecimalMath.sol";

import "forge-std/console.sol";
import "./LastFridays.sol";
import "./lyra-interfaces/IBaseExchangeAdapter.sol";
import "./lyra-interfaces/ILiquidityPool.sol";
import "./lyra-interfaces/IOptionGreekCache.sol";
import "./lyra-interfaces/IOptionMarket.sol";
import "./lib/VolGenerator.sol";

contract ListingManager is LastFridays {
  using DecimalMath for uint;

  struct QueuedBoard {
    uint queuedTime;
    uint baseIv;
    uint expiry;
    StrikeToAdd[] strikesToAdd;
  }

  struct QueuedStrikes {
    uint boardId;
    uint queuedTime;
    StrikeToAdd[] strikesToAdd;
  }

  struct StrikeToAdd {
    uint strikePrice;
    uint skew;
  }

  //////
  // In-memory
  struct BoardDetails {
    uint expiry;
    uint baseIv;
    StrikeDetails[] strikes;
  }

  struct StrikeDetails {
    uint strikePrice;
    uint skew;
  }

  IBaseExchangeAdapter immutable exchangeAdapter;
  ILiquidityPool immutable liquidityPool;
  IOptionGreekCache immutable optionGreekCache;
  IOptionMarket immutable optionMarket;
  // TODO: add OptionMarketGovernanceWrapper

  uint MAX_SPOT_DIFF = 0.05e18;
  uint MAX_TIME_DIFF = 3 hours;

  constructor(
    IBaseExchangeAdapter _exchangeAdapter,
    ILiquidityPool _liquidityPool,
    IOptionGreekCache _optionGreekCache,
    IOptionMarket _optionMarket
  ) {
    exchangeAdapter = _exchangeAdapter;
    liquidityPool = _liquidityPool;
    optionGreekCache = _optionGreekCache;
    optionMarket = _optionMarket;
  }

  ///////////////////////////////////////
  // Queues / Time lock / Risk Council //
  ///////////////////////////////////////

  // boardId => strikes
  // should block new strikes being added to the board if anything exists here
  mapping(uint => QueuedStrikes) queuedStrikes;

  // expiry => board;
  mapping(uint => QueuedBoard) queuedBoards;

  address riskCouncil;

  function setRiskCouncil(address _riskCouncil) external onlyOwner {}

  // TODO: any param setting? I think it can all be hardcoded and contract replaced if that's the desire.

  function vetoStrikeUpdate(uint boardId) external onlyRiskCouncil {
    // remove the QueuedStrikes for given boardId
  }

  function vetoQueuedBoard(uint expiry) external onlyRiskCouncil {
    // remove the QueuedBoard for given expiry
  }

  function fastForwardStrikeUpdate(uint boardId) external onlyRiskCouncil {}

  function fastForwardQueuedBoard(uint boardId) external onlyRiskCouncil {}

  modifier onlyRiskCouncil() {
    if (msg.sender != riskCouncil) {
      revert("only riskCouncil");
    }
    _;
  }

  modifier onlyOwner() {
    // TODO: inherit owned and delet this
    _;
  }

  ///////////////////////
  // Queue new strikes //
  ///////////////////////

  function findAndQueueStrikesForBoard(uint boardId) external requireCircuitBreakerInactive {
    // given no strikes queued for the board currently (and also check things like CBs in the liquidity pool)
    // for the given board, see if any strikes can be added based on the schema
    // if so; request the skews from the libraries
    // and then add to queue

    // Note: should be blocked when circuit breakers are firing

    // TODO: fetch data from newport contracts, fit into the format needed for the library and generate output/queue
  }

  function findAndQueueNewBoard(uint newExpiry) external requireCircuitBreakerInactive {
    // TODO: Figure out if any expiry is missing from our structure/within a max expiry
    // info in keynote presentation - basically need to hardcode monthly expiries for the next 10-20 years - then have
    // a process for adding weekly expiries up to 10-12 weeks

    // Note: should be blocked when circuit breakers are firing

    // TODO: fetch data from newport contracts, fit into the format needed for the library and generate output/queue
  }

  function executeQueuedStrikes(uint boardId) external requireCircuitBreakerInactive {
    // Note: should be blocked (probably actually just reverted?) when circuit breakers are firing
  }
  function executeQueuedBoard(uint expiry) external requireCircuitBreakerInactive {
    // Note: should be blocked (probably actually just reverted?) when circuit breakers are firing
  }

  function clearQueuedStrikes(uint boardId) external {
    if (liquidityPool.CBTimestamp() > block.timestamp) {
      // TODO: delete the queued strikes
    }
  }

  function clearQueuedBoard(uint expiry) external {
    if (liquidityPool.CBTimestamp() > block.timestamp) {
      // TODO: delete the queued board
    }
  }

  ///////////////////
  // Get new Board //
  ///////////////////

  function _getNewBoardData(uint expiry, uint[] memory newStrikes) internal view returns (QueuedBoard memory newBoard) {
    BoardDetails[] memory boardDetails = getAllBoardDetails();

    (VolGenerator.Board memory shortDated, VolGenerator.Board memory longDated) =
      _fetchSurroundingBoards(boardDetails, expiry);

    if (shortDated.orderedSkews.length == 0) {
      return _getQueuedBoardForEdgeBoard(expiry, newStrikes, longDated);
    } else if (longDated.orderedSkews.length == 0) {
      return _getQueuedBoardForEdgeBoard(expiry, newStrikes, shortDated);
    } else {
      // assume theres at least one board - _fetchSurroundingBoards will revert if there are no live boards.
      return _getQueuedBoardForMiddleBoard(expiry, newStrikes, shortDated, longDated);
    }
  }

  /// @notice Get the baseIv and skews for
  function _getQueuedBoardForMiddleBoard(
    uint expiry,
    uint[] memory newStrikes,
    VolGenerator.Board memory shortDated,
    VolGenerator.Board memory longDated
  ) internal view returns (QueuedBoard memory newBoard) {
    uint spotPrice = _getSpotPrice();
    uint tteAnnualised = _secToAnnualized(expiry - block.timestamp);
    newBoard.queuedTime = block.timestamp;
    newBoard.expiry = expiry;
    // TODO: what is this 1e18? copied from tests - assuming this is the right method
    newBoard.baseIv = VolGenerator.getSkewForNewBoard(spotPrice, tteAnnualised, 1e18, shortDated, longDated);
    // TODO: tests also divide baseIv by "defaultATMSkew" what is that?

    newBoard.strikesToAdd = new StrikeToAdd[](newStrikes.length);
    for (uint i = 0; i < newStrikes.length; ++i) {
      newBoard.strikesToAdd[i] = StrikeToAdd({
        strikePrice: newStrikes[i],
        skew: VolGenerator.getSkewForNewBoard(newStrikes[i], tteAnnualised, newBoard.baseIv, shortDated, longDated)
      });
    }
  }

  function _getQueuedBoardForEdgeBoard(uint expiry, uint[] memory newStrikes, VolGenerator.Board memory edgeBoard)
    internal
    view
    returns (QueuedBoard memory newBoard)
  {
    uint spotPrice = _getSpotPrice();
    uint tteAnnualised = _secToAnnualized(expiry - block.timestamp);
    newBoard.queuedTime = block.timestamp;
    newBoard.expiry = expiry;
    // TODO: what is this 1e18? copied from tests - assuming this is the right method
    newBoard.baseIv = VolGenerator.getSkewForNewBoard(spotPrice, tteAnnualised, 1e18, spotPrice, edgeBoard);
    // TODO: tests also divide baseIv by "defaultATMSkew" what is that?

    newBoard.strikesToAdd = new StrikeToAdd[](newStrikes.length);
    for (uint i = 0; i < newStrikes.length; ++i) {
      newBoard.strikesToAdd[i] = StrikeToAdd({
        strikePrice: newStrikes[i],
        skew: VolGenerator.getSkewForNewBoard(newStrikes[i], tteAnnualised, newBoard.baseIv, spotPrice, edgeBoard)
      });
    }
  }

  /// @notice Gets the closest board on both sides of the given expiry, converting them to the format required for the vol generator
  function _fetchSurroundingBoards(BoardDetails[] memory boardDetails, uint expiry)
    internal
    view
    returns (VolGenerator.Board memory shortDated, VolGenerator.Board memory longDated)
  {
    /**
     * TODO: testcases:
     * Expiry on short edge:
     * 1. two boards, in order -> first index is shortDated, nothing for longDated
     * 2. two boards, out of order -> second index is shortDated, nothing for longDated
     * 3. two boards, same expiry (different to passed in expiry) -> first index is shortDated
     * 4. one board, shortDated will be the result
     * Expiry on long edge:
     * same 4 cases, just returns longDated and not shortDated
     * Expiry in the middle:
     * one on one side, two on the other, out of order - twice
     * Misc:
     * boardDetails length of 0 - reverts
     * boardDetails has same expiry as requested - reverts
     */
    if (boardDetails.length == 0) {
      revert("no boards");
    }

    uint shortIndex = type(uint).max;
    uint longIndex = type(uint).max;
    for (uint i = 0; i < boardDetails.length; i++) {
      BoardDetails memory current = boardDetails[i];
      if (current.expiry < expiry) {
        // If the board's expiry is less than the expiry we want to add - it is a shortDated board
        if (shortIndex == type(uint).max || boardDetails[shortIndex].expiry < current.expiry) {
          // If the current board is closer, update to the current board
          shortIndex = i;
        }
      } else if (current.expiry > expiry) {
        // If the board's expiry is larger than the expiry we want to add - it is a longDated board
        if (longIndex == type(uint).max || boardDetails[longIndex].expiry > current.expiry) {
          longIndex = i;
        }
      } else {
        revert("expiry exists");
      }
    }

    // At this point, one of short/long is guaranteed to be set - as the boardDetails length is > 0
    // and the expiry being used already causes reverts
    if (longIndex != type(uint).max) {
      longDated = _boardDetailsToVolGeneratorBoard(boardDetails[longIndex]);
    }

    if (shortIndex != type(uint).max) {
      shortDated = _boardDetailsToVolGeneratorBoard(boardDetails[shortIndex]);
    }

    return (shortDated, longDated);
  }

  function _boardDetailsToVolGeneratorBoard(BoardDetails memory details)
    internal
    view
    returns (VolGenerator.Board memory)
  {
    /**
     * Tests:
     * 1. pass in a board with unsorted strikes, make sure output is correct
     * 2. board with no strikes ?
     */
    uint numStrikes = details.strikes.length;

    quickSortStrikes(details.strikes, 0, int(numStrikes - 1));

    uint[] memory orderedStrikePrices = new uint[](numStrikes);
    uint[] memory orderedSkews = new uint[](numStrikes);

    for (uint i = 0; i < numStrikes; i++) {
      console.log("details.strikes[i].skew", details.strikes[i].skew);
      orderedStrikePrices[i] = details.strikes[i].strikePrice;
      orderedSkews[i] = details.strikes[i].skew;
    }

    return VolGenerator.Board({
      // This will revert for expired boards TODO: add a test for this
      tAnnualized: _secToAnnualized(details.expiry - block.timestamp),
      baseIv: details.baseIv,
      orderedStrikePrices: orderedStrikePrices,
      orderedSkews: orderedSkews
    });
  }

  function getAllBoardDetails() public view returns (BoardDetails[] memory boardDetails) {
    console.log("Getting all board details");
    uint[] memory liveBoards = optionMarket.getLiveBoards();
    boardDetails = new BoardDetails[](liveBoards.length);
    for (uint i = 0; i < liveBoards.length; ++i) {
      (IOptionMarket.OptionBoard memory board, IOptionMarket.Strike[] memory strikes,,,) =
        optionMarket.getBoardAndStrikeDetails(liveBoards[i]);
      StrikeDetails[] memory strikeDetails = new StrikeDetails[](strikes.length);
      for (uint j = 0; j < strikes.length; ++j) {
        strikeDetails[j] = StrikeDetails({strikePrice: strikes[j].strikePrice, skew: strikes[j].skew});
      }
      boardDetails[i] = BoardDetails({expiry: board.expiry, baseIv: board.iv, strikes: strikeDetails});
    }
    return boardDetails;
  }

  function _getSpotPrice() internal view returns (uint spotPrice) {
    return exchangeAdapter.getSpotPriceForMarket(address(optionMarket), IBaseExchangeAdapter.PriceType.REFERENCE);
  }

  /// TODO: can be moved to library functions
  function _secToAnnualized(uint sec) public pure returns (uint) {
    return (sec * 1e18) / uint(365 days);
  }

  modifier requireCircuitBreakerInactive() {
    if (liquidityPool.CBTimestamp() > block.timestamp) {
      revert("CircuitBreaker live");
    }
    _;
  }

  function quickSortStrikes(StrikeDetails[] memory arr, int left, int right) internal pure {
    // TODO: untested, just copy pasted
    int i = left;
    int j = right;
    if (i == j) {
      return;
    }
    uint pivot = arr[uint(left + (right - left) / 2)].strikePrice;
    while (i <= j) {
      while (arr[uint(i)].strikePrice < pivot) {
        i++;
      }
      while (pivot < arr[uint(j)].strikePrice) {
        j--;
      }
      if (i <= j) {
        (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
        i++;
        j--;
      }
    }
    if (left < j) {
      quickSortStrikes(arr, left, j);
    }
    if (i < right) {
      quickSortStrikes(arr, i, right);
    }
  }
}
