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
import "./lib/StrikePriceGenerator.sol";
import "./lib/ExpiryGenerator.sol";

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

  uint boardQueueTime = 1 days;
  uint strikeQueueTime = 1 days;
  uint queueStaleTime = 2 days;

  uint constant NEW_BOARD_MIN_EXPIRY = 7 days;
  uint constant NEW_STRIKE_MIN_EXPIRY = 2 days;
  uint constant NUM_WEEKLIES = 8;
  uint constant NUM_MONTHLIES = 3;

  uint constant MAX_SCALED_MONEYNESS = 1.2 ether;
  uint constant MAX_NUM_STRIKES = 25;

  uint[] PIVOTS = [
    1 ether,
    2 ether,
    5 ether,
    10 ether,
    20 ether,
    50 ether,
    100 ether,
    200 ether,
    500 ether,
    1000 ether,
    2000 ether,
    5000 ether,
    10000 ether,
    20000 ether,
    50000 ether,
    100000 ether,
    200000 ether,
    500000 ether,
    1000000 ether,
    2000000 ether,
    5000000 ether,
    10000000 ether
  ];

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

  ////
  // onlyOwner
  ////

  function setRiskCouncil(address _riskCouncil) external onlyOwner {
    riskCouncil = _riskCouncil;
  }

  // TODO: any param setting? Yeah probably want to reduce the queue time only
  function setQueueParams(uint _boardQueueTime, uint _strikeQueueTime, uint _queueStaleTime) external onlyOwner {
    boardQueueTime = _boardQueueTime;
    strikeQueueTime = _strikeQueueTime;
    queueStaleTime = _queueStaleTime;
  }

  modifier onlyOwner() {
    // TODO: inherit owned and delet this
    _;
  }

  /////
  // onlyRiskCouncil
  /////

  function vetoStrikeUpdate(uint boardId) external onlyRiskCouncil {
    // remove the QueuedStrikes for given boardId
    delete queuedStrikes[boardId];
  }

  function vetoQueuedBoard(uint expiry) external onlyRiskCouncil {
    // remove the QueuedBoard for given expiry
    delete queuedBoards[expiry];
  }

  function fastForwardStrikeUpdate(uint boardId) external onlyRiskCouncil {
    // TODO: just change the queued time?
    _executeQueuedStrikes(boardId);
  }

  function fastForwardQueuedBoard(uint expiry) external onlyRiskCouncil {
    _executeQueuedBoard(expiry);
  }

  modifier onlyRiskCouncil() {
    if (msg.sender != riskCouncil) {
      revert("only riskCouncil");
    }
    _;
  }

  /////////////
  // Execute //
  /////////////

  function executeQueuedStrikes(uint boardId) public {
    if (isCBActive()) {
      delete queuedStrikes[boardId];
      return;
    }

    if (queuedStrikes[boardId].queuedTime + queueStaleTime > block.timestamp) {
      revert("strike stale");
    }

    if (block.timestamp < queuedStrikes[boardId].queuedTime + strikeQueueTime) {
      revert("too early");
    }
    _executeQueuedStrikes(boardId);
  }

  function executeQueuedBoard(uint expiry) public {
    if (isCBActive()) {
      delete queuedBoards[expiry];
      return;
    }

    QueuedBoard memory queueBoard = queuedBoards[expiry];
    // if it is stale (staleQueueTime), delete the entry
    if (queueBoard.queuedTime + queueStaleTime > block.timestamp) {
      revert("board stale");
    }

    // execute the queued board if the required time has passed
    if (block.timestamp < queueBoard.queuedTime + boardQueueTime) {
      revert("too early");
    }

    _executeQueuedBoard(expiry);
  }

  function _executeQueuedBoard(uint expiry) internal {
    QueuedBoard memory queueBoard = queuedBoards[expiry];
    uint[] memory strikes = new uint[](queueBoard.strikesToAdd.length);
    uint[] memory skews = new uint[](queueBoard.strikesToAdd.length);

    for (uint i; i < queueBoard.strikesToAdd.length; i++) {
      strikes[i] = queueBoard.strikesToAdd[i].strikePrice;
      skews[i] = queueBoard.strikesToAdd[i].skew;
    }

    optionMarket.createOptionBoard(
      queueBoard.expiry,
      queueBoard.baseIv,
      strikes,
      skews,
      false
    );

    delete queuedBoards[expiry];
  }

  function _executeQueuedStrikes(uint boardId) internal {
    QueuedStrikes memory queueStrikes = queuedStrikes[boardId];
    for (uint i; i < queuedStrikes[boardId].strikesToAdd.length; i++) {
      optionMarket.addStrikeToBoard(
        boardId,
        queuedStrikes[boardId].strikesToAdd[0].strikePrice,
        queuedStrikes[boardId].strikesToAdd[0].skew);
    }
    delete queuedStrikes[boardId];
  }

  ///////////////////////
  // Queue new strikes //
  ///////////////////////

  // given no strikes queued for the board currently (and also check things like CBs in the liquidity pool)
  // for the given board, see if any strikes can be added based on the schema
  // if so; request the skews from the libraries
  // and then add to queue
  function findAndQueueStrikesForBoard(uint boardId) external {
    if (isCBActive()) {
      revert("CB active");
    }

    if (queuedStrikes[boardId].boardId != 0) {
      revert("strikes already queued");
    }

    BoardDetails memory boardDetails = getBoardDetails(boardId);

    if (boardDetails.expiry < block.timestamp + NEW_STRIKE_MIN_EXPIRY) {
      revert("too close to expiry");
    }

    _queueNewStrikes(boardId, boardDetails);
  }

  function queueNewBoard(uint newExpiry) external {
    if (isCBActive()) {
      revert("CB active");
    }

    _validateNewBoardExpiry(newExpiry);

    if (queuedBoards[newExpiry].expiry != 0) {
      revert("board already queued");
    }

    _queueNewBoard(newExpiry);
  }

  function _validateNewBoardExpiry(uint expiry) internal view {
    console.log(block.timestamp);
    console.log(expiry);
    if (expiry < block.timestamp + NEW_BOARD_MIN_EXPIRY) {
      revert("expiry too short");
    }

    uint[] memory validExpiries = ExpiryGenerator.getExpiries(NUM_WEEKLIES, NUM_MONTHLIES, block.timestamp, lastFridays);

    for (uint i = 0; i < validExpiries.length; ++i) {
      if (validExpiries[i] == expiry) {
        // matches a valid expiry. If the expiry already exists, it will be caught in _fetchSurroundingBoards()
        return;
      }
    }
    revert("expiry doesn't match format");
  }

  ///////
  // Add strikes to board
  /////////

  function _queueNewStrikes(uint boardId, BoardDetails memory boardDetails) internal {
    uint spotPrice = _getSpotPrice();

    VolGenerator.Board memory board = _boardDetailsToVolGeneratorBoard(boardDetails);

    (uint[] memory newStrikes, uint numNewStrikes) = StrikePriceGenerator.getNewStrikes(
      _secToAnnualized(boardDetails.expiry - block.timestamp),
      spotPrice,
      MAX_SCALED_MONEYNESS,
      MAX_NUM_STRIKES,
      board.orderedStrikePrices,
      PIVOTS
    );

    queuedStrikes[boardId].queuedTime = block.timestamp;
    queuedStrikes[boardId].boardId = boardId; // todo: is boardId even necessary?

    for (uint i = 0; i < numNewStrikes; i++) {
      queuedStrikes[boardId].strikesToAdd.push(
        StrikeToAdd({strikePrice: newStrikes[i], skew: VolGenerator.getSkewForLiveBoard(newStrikes[i], board)})
      );
    }
  }

  ///////////////////
  // Get new Board //
  ///////////////////

  /// @dev Internal queueBoard function, assumes the expiry is valid (but does not know if the expiry is already used)
  function _queueNewBoard(uint newExpiry) internal {
    (uint baseIv, StrikeToAdd[] memory strikesToAdd) = _getNewBoardData(newExpiry);

    queuedBoards[newExpiry].queuedTime = block.timestamp;
    queuedBoards[newExpiry].expiry = newExpiry;
    queuedBoards[newExpiry].baseIv = baseIv;
    for (uint i = 0; i < strikesToAdd.length; i++) {
      queuedBoards[newExpiry].strikesToAdd.push(strikesToAdd[i]);
    }
  }

  function _getNewBoardData(uint expiry) internal view returns (uint baseIv, StrikeToAdd[] memory strikesToAdd) {
    uint spotPrice = _getSpotPrice();

    (uint[] memory newStrikes, uint numNewStrikes) = StrikePriceGenerator.getNewStrikes(
      _secToAnnualized(expiry - block.timestamp),
      spotPrice,
      MAX_SCALED_MONEYNESS,
      MAX_NUM_STRIKES,
      new uint[](0),
      PIVOTS
    );

    BoardDetails[] memory boardDetails = getAllBoardDetails();

    (VolGenerator.Board memory shortDated, VolGenerator.Board memory longDated) =
      _fetchSurroundingBoards(boardDetails, expiry);

    if (shortDated.orderedSkews.length == 0) {
      return _getQueuedBoardForEdgeBoard(spotPrice, expiry, newStrikes, numNewStrikes, longDated);
    } else if (longDated.orderedSkews.length == 0) {
      return _getQueuedBoardForEdgeBoard(spotPrice, expiry, newStrikes, numNewStrikes, shortDated);
    } else {
      // assume theres at least one board - _fetchSurroundingBoards will revert if there are no live boards.
      return _getQueuedBoardForMiddleBoard(spotPrice, expiry, newStrikes, numNewStrikes, shortDated, longDated);
    }
  }

  /// @notice Get the baseIv and skews for
  function _getQueuedBoardForMiddleBoard(
    uint spotPrice,
    uint expiry,
    uint[] memory newStrikes,
    uint numNewStrikes,
    VolGenerator.Board memory shortDated,
    VolGenerator.Board memory longDated
  ) internal view returns (uint baseIv, StrikeToAdd[] memory strikesToAdd) {
    uint tteAnnualised = _secToAnnualized(expiry - block.timestamp);

    // Note: we treat the default ATM skew as 1.0
    // We pass in 1.0 as the baseIv... because.... TODO: why exactly?
    baseIv = VolGenerator.getSkewForNewBoard(spotPrice, tteAnnualised, 1e18, shortDated, longDated);

    strikesToAdd = new StrikeToAdd[](numNewStrikes);
    for (uint i = 0; i < numNewStrikes; ++i) {
      strikesToAdd[i] = StrikeToAdd({
        strikePrice: newStrikes[i],
        skew: VolGenerator.getSkewForNewBoard(newStrikes[i], tteAnnualised, baseIv, shortDated, longDated)
      });
    }
  }

  function _getQueuedBoardForEdgeBoard(
    uint spotPrice,
    uint expiry,
    uint[] memory newStrikes,
    uint numNewStrikes,
    VolGenerator.Board memory edgeBoard
  ) internal view returns (uint baseIv, StrikeToAdd[] memory strikesToAdd) {
    uint spotPrice = _getSpotPrice();
    uint tteAnnualised = _secToAnnualized(expiry - block.timestamp);

    // Note: we treat the default ATM skew as 1.0
    // We pass in 1.0 as the baseIv... because.... TODO: why exactly?
    baseIv = VolGenerator.getSkewForNewBoard(spotPrice, tteAnnualised, 1e18, spotPrice, edgeBoard);

    strikesToAdd = new StrikeToAdd[](numNewStrikes);

    for (uint i = 0; i < numNewStrikes; ++i) {
      strikesToAdd[i] = StrikeToAdd({
        strikePrice: newStrikes[i],
        skew: VolGenerator.getSkewForNewBoard(newStrikes[i], tteAnnualised, baseIv, spotPrice, edgeBoard)
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

  /////////////////
  // Utils/views //
  /////////////////

  function _boardDetailsToVolGeneratorBoard(BoardDetails memory details)
    internal
    view
    returns (VolGenerator.Board memory)
  {
    /**
     * TODO:
     * Tests:
     * 1. pass in a board with unsorted strikes, make sure output is correct
     * 2. board with no strikes ?
     */
    uint numStrikes = details.strikes.length;

    quickSortStrikes(details.strikes, 0, int(numStrikes - 1));

    uint[] memory orderedStrikePrices = new uint[](numStrikes);
    uint[] memory orderedSkews = new uint[](numStrikes);

    for (uint i = 0; i < numStrikes; i++) {
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
    uint[] memory liveBoards = optionMarket.getLiveBoards();
    boardDetails = new BoardDetails[](liveBoards.length);
    for (uint i = 0; i < liveBoards.length; ++i) {
      boardDetails[i] = getBoardDetails(liveBoards[i]);
    }
    return boardDetails;
  }

  function getBoardDetails(uint boardId) public view returns (BoardDetails memory boardDetails) {
    (IOptionMarket.OptionBoard memory board, IOptionMarket.Strike[] memory strikes,,,) =
      optionMarket.getBoardAndStrikeDetails(boardId);
    StrikeDetails[] memory strikeDetails = new StrikeDetails[](strikes.length);
    for (uint i = 0; i < strikes.length; ++i) {
      strikeDetails[i] = StrikeDetails({strikePrice: strikes[i].strikePrice, skew: strikes[i].skew});
    }
    return BoardDetails({expiry: board.expiry, baseIv: board.iv, strikes: strikeDetails});
  }

  function _getSpotPrice() internal view returns (uint spotPrice) {
    return exchangeAdapter.getSpotPriceForMarket(address(optionMarket), IBaseExchangeAdapter.PriceType.REFERENCE);
  }

  /// TODO: can be moved to library functions
  function _secToAnnualized(uint sec) public pure returns (uint) {
    return (sec * 1e18) / uint(365 days);
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

  function isCBActive() internal returns (bool) {
    return liquidityPool.CBTimestamp() > block.timestamp;
  }
}
