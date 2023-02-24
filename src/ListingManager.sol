//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

// Interfaces
import "./lyra-interfaces/IBaseExchangeAdapter.sol";
import "./lyra-interfaces/ILiquidityPool.sol";
import "./lyra-interfaces/IOptionGreekCache.sol";
import "./lyra-interfaces/IOptionMarket.sol";
import "./lyra-interfaces/IOptionMarketGovernanceWrapper.sol";

// Libraries
import "../lib/lyra-utils/src/decimals/DecimalMath.sol";
import "./lib/VolGenerator.sol";
import "./lib/StrikePriceGenerator.sol";
import "./lib/ExpiryGenerator.sol";

// Inherited
import "./ListingManagerLibrarySettings.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable2Step.sol";

contract ListingManager is ListingManagerLibrarySettings, Ownable2Step {
  using DecimalMath for uint;

  /////////////////////
  // Storage structs //
  /////////////////////
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

  ///////////////
  // In-memory //
  ///////////////
  struct BoardDetails {
    uint expiry;
    uint baseIv;
    StrikeDetails[] strikes;
  }

  struct StrikeDetails {
    uint strikePrice;
    uint skew;
  }

  ///////////////
  // Variables //
  ///////////////
  IBaseExchangeAdapter immutable exchangeAdapter;
  ILiquidityPool immutable liquidityPool;
  IOptionGreekCache immutable optionGreekCache;
  IOptionMarket immutable optionMarket;
  IOptionMarketGovernanceWrapper immutable governanceWrapper;

  address riskCouncil;

  /// @notice How long a board must be queued before it can be publicly executed
  uint public boardQueueTime = 1 days;
  /// @notice How long new strikes must be queued before they can be publicly executed
  uint public strikeQueueTime = 1 days;
  /// @notice How long a queued item can exist after queueTime before being considered stale and removed
  uint public queueStaleTime = 1 days;
  uint public maxStrikesPerExecute = 5;

  // boardId => strikes
  mapping(uint => QueuedStrikes) queuedStrikes;

  // expiry => board;
  mapping(uint => QueuedBoard) queuedBoards;

  constructor(
    IBaseExchangeAdapter _exchangeAdapter,
    ILiquidityPool _liquidityPool,
    IOptionGreekCache _optionGreekCache,
    IOptionMarket _optionMarket,
    IOptionMarketGovernanceWrapper _governanceWrapper
  ) Ownable2Step() {
    exchangeAdapter = _exchangeAdapter;
    liquidityPool = _liquidityPool;
    optionGreekCache = _optionGreekCache;
    optionMarket = _optionMarket;
    governanceWrapper = _governanceWrapper;
  }

  ///////////
  // Admin //
  ///////////
  function setRiskCouncil(address _riskCouncil) external onlyOwner {
    riskCouncil = _riskCouncil;
    emit LM_RiskCouncilSet(_riskCouncil);
  }

  function setQueueParams(uint _boardQueueTime, uint _strikeQueueTime, uint _queueStaleTime) external onlyOwner {
    boardQueueTime = _boardQueueTime;
    strikeQueueTime = _strikeQueueTime;
    queueStaleTime = _queueStaleTime;
    emit LM_QueueParamsSet(_boardQueueTime, _strikeQueueTime, _queueStaleTime);
  }

  /////////////////////
  // onlyRiskCouncil //
  /////////////////////

  /// @notice Forcefully remove the QueuedStrikes for given boardId
  function vetoStrikeUpdate(uint boardId) external onlyRiskCouncil {
    emit LM_StrikeUpdateVetoed(boardId, queuedStrikes[boardId]);
    delete queuedStrikes[boardId];
  }

  /// @notice Forcefully remove the QueuedBoard for given expiry
  function vetoQueuedBoard(uint expiry) external onlyRiskCouncil {
    emit LM_BoardVetoed(expiry, queuedBoards[expiry]);
    delete queuedBoards[expiry];
  }

  /// @notice Bypass the delay for adding strikes to a board, execute immediately
  function fastForwardStrikeUpdate(uint boardId, uint executionLimit) external onlyRiskCouncil {
    _executeQueuedStrikes(boardId, executionLimit);
  }

  /// @notice Bypass the delay for adding a new board, execute immediately
  function fastForwardQueuedBoard(uint expiry) external onlyRiskCouncil {
    _executeQueuedBoard(expiry);
  }

  ////////////////////////////
  // Execute queued strikes //
  ////////////////////////////

  function executeQueuedStrikes(uint boardId, uint executionLimit) public {
    if (isCBActive()) {
      emit LM_CBClearQueuedStrikes(msg.sender, boardId);
      delete queuedStrikes[boardId];
      return;
    }

    if (queuedStrikes[boardId].queuedTime + queueStaleTime + strikeQueueTime < block.timestamp) {
      emit LM_QueuedStrikesStale(
        msg.sender, boardId, queuedStrikes[boardId].queuedTime + queueStaleTime + strikeQueueTime, block.timestamp
        );

      delete queuedStrikes[boardId];
      return;
    }

    if (queuedStrikes[boardId].queuedTime + strikeQueueTime > block.timestamp) {
      revert LM_TooEarlyToExecuteStrike(boardId, queuedStrikes[boardId].queuedTime, block.timestamp);
    }
    _executeQueuedStrikes(boardId, executionLimit);
  }

  function _executeQueuedStrikes(uint boardId, uint executionLimit) internal {
    uint strikesLength = queuedStrikes[boardId].strikesToAdd.length;
    uint numToExecute = strikesLength > executionLimit ? executionLimit : strikesLength;

    for (uint i = strikesLength; i > strikesLength - numToExecute; --i) {
      governanceWrapper.addStrikeToBoard(
        optionMarket,
        boardId,
        queuedStrikes[boardId].strikesToAdd[i - 1].strikePrice,
        queuedStrikes[boardId].strikesToAdd[i - 1].skew
      );
      emit LM_QueuedStrikeExecuted(msg.sender, boardId, queuedStrikes[boardId].strikesToAdd[i - 1]);
      queuedStrikes[boardId].strikesToAdd.pop();
    }

    if (queuedStrikes[boardId].strikesToAdd.length == 0) {
      emit LM_QueuedStrikesAllExecuted(msg.sender, boardId);
      delete queuedStrikes[boardId];
    }
  }

  //////////////////////////
  // Execute queued board //
  //////////////////////////

  function executeQueuedBoard(uint expiry) public {
    if (isCBActive()) {
      emit LM_CBClearQueuedBoard(msg.sender, expiry);
      delete queuedBoards[expiry];
      return;
    }

    QueuedBoard memory queuedBoard = queuedBoards[expiry];
    // if it is stale (staleQueueTime), delete the entry
    revert LM_BoardStale(expiry, queueStaleTime, block.timestamp);
    if (queuedBoard.queuedTime + boardQueueTime + queueStaleTime > block.timestamp) {
      emit LM_QueuedBoardStale(
        msg.sender, expiry, queuedBoard.queuedTime + boardQueueTime + queueStaleTime, block.timestamp
        );
      delete queuedBoards[expiry];
      return;
    }

    // execute the queued board if the required time has passed
    if (queuedBoard.queuedTime + boardQueueTime > block.timestamp) {
      revert LM_TooEarlyToExecuteBoard(expiry, queuedBoard.queuedTime, block.timestamp);
    }

    _executeQueuedBoard(expiry);
  }

  function _executeQueuedBoard(uint expiry) internal {
    QueuedBoard memory queuedBoard = queuedBoards[expiry];
    uint[] memory strikes = new uint[](queuedBoard.strikesToAdd.length);
    uint[] memory skews = new uint[](queuedBoard.strikesToAdd.length);

    for (uint i; i < queuedBoard.strikesToAdd.length; i++) {
      strikes[i] = queuedBoard.strikesToAdd[i].strikePrice;
      skews[i] = queuedBoard.strikesToAdd[i].skew;
    }

    uint boardId =
      governanceWrapper.createOptionBoard(optionMarket, queuedBoard.expiry, queuedBoard.baseIv, strikes, skews, false);

    emit LM_QueuedBoardExecuted(msg.sender, boardId, queuedBoard);
    delete queuedBoards[expiry];
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
      revert LM_CBActive(block.timestamp);
    }

    if (queuedStrikes[boardId].boardId != 0) {
      revert LM_strikesAlreadyQueued(boardId);
    }

    BoardDetails memory boardDetails = getBoardDetails(boardId);

    if (boardDetails.expiry < block.timestamp + NEW_STRIKE_MIN_EXPIRY) {
      revert LM_TooCloseToExpiry(boardDetails.expiry, boardId);
    }

    _queueNewStrikes(boardId, boardDetails);
  }

  function _queueNewStrikes(uint boardId, BoardDetails memory boardDetails) internal {
    uint spotPrice = _getSpotPrice();

    VolGenerator.Board memory board = _toVolGeneratorBoard(boardDetails);

    (uint[] memory newStrikes, uint numNewStrikes) = StrikePriceGenerator.getNewStrikes(
      _secToAnnualized(boardDetails.expiry - block.timestamp),
      spotPrice,
      MAX_SCALED_MONEYNESS,
      MAX_NUM_STRIKES,
      board.orderedStrikePrices,
      PIVOTS
    );

    if (numNewStrikes == 0) {
      revert LM_NoNewStrikesGenerated(boardId);
    }

    queuedStrikes[boardId].queuedTime = block.timestamp;
    queuedStrikes[boardId].boardId = boardId;

    for (uint i = 0; i < numNewStrikes; i++) {
      queuedStrikes[boardId].strikesToAdd.push(
        StrikeToAdd({strikePrice: newStrikes[i], skew: VolGenerator.getSkewForLiveBoard(newStrikes[i], board)})
      );
    }
  }

  /////////////////////
  // Queue new Board //
  /////////////////////

  function queueNewBoard(uint newExpiry) external {
    if (isCBActive()) {
      revert LM_CBActive(block.timestamp);
    }

    _validateNewBoardExpiry(newExpiry);

    if (queuedBoards[newExpiry].expiry != 0) {
      revert LM_BoardAlreadyQueued(newExpiry);
    }

    _queueNewBoard(newExpiry);
  }

  function _validateNewBoardExpiry(uint expiry) internal view {
    if (expiry < block.timestamp + NEW_BOARD_MIN_EXPIRY) {
      revert LM_ExpiryTooShort(expiry, NEW_BOARD_MIN_EXPIRY);
    }

    uint[] memory validExpiries = getValidExpiries();
    for (uint i = 0; i < validExpiries.length; ++i) {
      if (validExpiries[i] == expiry) {
        // matches a valid expiry. If the expiry already exists, it will be caught in _fetchSurroundingBoards()
        return;
      }
    }
    revert LM_ExpiryDoesntMatchFormat(expiry);
  }

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
      return _extrapolateBoard(spotPrice, expiry, newStrikes, numNewStrikes, longDated);
    } else if (longDated.orderedSkews.length == 0) {
      return _extrapolateBoard(spotPrice, expiry, newStrikes, numNewStrikes, shortDated);
    } else {
      // assume theres at least one board - _fetchSurroundingBoards will revert if there are no live boards.
      return _interpolateBoard(spotPrice, expiry, newStrikes, numNewStrikes, shortDated, longDated);
    }
  }

  /// @notice Gets the closest board on both sides of the given expiry, converting them to the format required for the vol generator
  function _fetchSurroundingBoards(BoardDetails[] memory boardDetails, uint expiry)
    internal
    view
    returns (VolGenerator.Board memory shortDated, VolGenerator.Board memory longDated)
  {
    if (boardDetails.length == 0) {
      revert LM_NoBoards();
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
        revert LM_ExpiryExists(expiry);
      }
    }

    // At this point, one of short/long is guaranteed to be set - as the boardDetails length is > 0
    // and the expiry being used already causes reverts
    if (longIndex != type(uint).max) {
      longDated = _toVolGeneratorBoard(boardDetails[longIndex]);
    }

    if (shortIndex != type(uint).max) {
      shortDated = _toVolGeneratorBoard(boardDetails[shortIndex]);
    }
    return (shortDated, longDated);
  }

  /// @notice Get the baseIv and skews for
  function _interpolateBoard(
    uint spotPrice,
    uint expiry,
    uint[] memory newStrikes,
    uint numNewStrikes,
    VolGenerator.Board memory shortDated,
    VolGenerator.Board memory longDated
  ) internal view returns (uint baseIv, StrikeToAdd[] memory strikesToAdd) {
    uint tteAnnualised = _secToAnnualized(expiry - block.timestamp);

    // Note: we treat the default ATM skew as 1.0, by passing in baseIv as 1, we can determine what the "skew" should be
    // if baseIv is 1. Then we flip the equation to get the baseIv for a skew of 1.0.
    baseIv = VolGenerator.getSkewForNewBoard(spotPrice, tteAnnualised, DecimalMath.UNIT, shortDated, longDated);

    strikesToAdd = new StrikeToAdd[](numNewStrikes);
    for (uint i = 0; i < numNewStrikes; ++i) {
      strikesToAdd[i] = StrikeToAdd({
        strikePrice: newStrikes[i],
        skew: VolGenerator.getSkewForNewBoard(newStrikes[i], tteAnnualised, baseIv, shortDated, longDated)
      });
    }
  }

  function _extrapolateBoard(
    uint spotPrice,
    uint expiry,
    uint[] memory newStrikes,
    uint numNewStrikes,
    VolGenerator.Board memory edgeBoard
  ) internal view returns (uint baseIv, StrikeToAdd[] memory strikesToAdd) {
    uint tteAnnualised = _secToAnnualized(expiry - block.timestamp);

    // Note: we treat the default ATM skew as 1.0, by passing in baseIv as 1, we can determine what the "skew" should be
    // if baseIv is 1. Then we flip the equation to get the baseIv for a skew of 1.0.
    baseIv = VolGenerator.getSkewForNewBoard(spotPrice, tteAnnualised, DecimalMath.UNIT, spotPrice, edgeBoard);

    strikesToAdd = new StrikeToAdd[](numNewStrikes);

    for (uint i = 0; i < numNewStrikes; ++i) {
      strikesToAdd[i] = StrikeToAdd({
        strikePrice: newStrikes[i],
        skew: VolGenerator.getSkewForNewBoard(newStrikes[i], tteAnnualised, baseIv, spotPrice, edgeBoard)
      });
    }
  }

  ///////////
  // Utils //
  ///////////

  function _toVolGeneratorBoard(BoardDetails memory details) internal view returns (VolGenerator.Board memory) {
    uint numStrikes = details.strikes.length;

    _quickSortStrikes(details.strikes, 0, int(numStrikes - 1));

    uint[] memory orderedStrikePrices = new uint[](numStrikes);
    uint[] memory orderedSkews = new uint[](numStrikes);

    for (uint i = 0; i < numStrikes; i++) {
      orderedStrikePrices[i] = details.strikes[i].strikePrice;
      orderedSkews[i] = details.strikes[i].skew;
    }

    return VolGenerator.Board({
      // This will revert for expired boards
      tAnnualized: _secToAnnualized(details.expiry - block.timestamp),
      baseIv: details.baseIv,
      orderedStrikePrices: orderedStrikePrices,
      orderedSkews: orderedSkews
    });
  }

  ///////////////////////////
  // Lyra Protocol getters //
  ///////////////////////////

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

    IOptionGreekCache.BoardGreeksView memory boardGreeks = optionGreekCache.getBoardGreeksView(boardId);

    StrikeDetails[] memory strikeDetails = new StrikeDetails[](strikes.length);
    for (uint i = 0; i < strikes.length; ++i) {
      strikeDetails[i] = StrikeDetails({strikePrice: strikes[i].strikePrice, skew: boardGreeks.skewGWAVs[i]});
    }
    return BoardDetails({expiry: board.expiry, baseIv: boardGreeks.ivGWAV, strikes: strikeDetails});
  }

  function _getSpotPrice() internal view returns (uint spotPrice) {
    return exchangeAdapter.getSpotPriceForMarket(address(optionMarket), IBaseExchangeAdapter.PriceType.REFERENCE);
  }

  function isCBActive() internal view returns (bool) {
    return liquidityPool.CBTimestamp() > block.timestamp;
  }

  ///////////
  // Views //
  ///////////

  function getQueuedBoard(uint expiry) external view returns (QueuedBoard memory) {
    return queuedBoards[expiry];
  }

  function getQueuedStrikes(uint boardId) external view returns (QueuedStrikes memory) {
    return queuedStrikes[boardId];
  }

  function getValidExpiries() public view returns (uint[] memory validExpiries) {
    return ExpiryGenerator.getExpiries(NUM_WEEKLIES, NUM_MONTHLIES, block.timestamp, LAST_FRIDAYS);
  }

  //////////
  // Misc //
  //////////

  function _secToAnnualized(uint sec) public pure returns (uint) {
    return (sec * DecimalMath.UNIT) / uint(365 days);
  }

  function _quickSortStrikes(StrikeDetails[] memory arr, int left, int right) internal pure {
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
      _quickSortStrikes(arr, left, j);
    }
    if (i < right) {
      _quickSortStrikes(arr, i, right);
    }
  }

  ///////////////
  // Modifiers //
  ///////////////
  modifier onlyRiskCouncil() {
    if (msg.sender != riskCouncil) {
      revert LM_OnlyRiskCouncil(msg.sender);
    }
    _;
  }

  /////////////
  // Events ///
  /////////////

  event LM_RiskCouncilSet(address indexed riskCouncil);
  event LM_QueueParamsSet(uint boardQueuedTime, uint strikesQueuedTime, uint staleTime);
  event LM_StrikeUpdateVetoed(uint indexed boardId, QueuedStrikes exectuedStrike);
  event LM_BoardVetoed(uint indexed expiry, QueuedBoard queuedBoards);
  event LM_QueuedStrikeExecuted(address indexed caller, uint indexed boardId, StrikeToAdd strikeAdded);
  event LM_QueuedStrikesAllExecuted(address indexed caller, uint indexed boardId);
  event LM_QueuedBoardExecuted(address indexed caller, uint indexed expiry, QueuedBoard board);

  event LM_QueuedStrikesStale(address indexed caller, uint indexed boardId, uint staleTimestamp, uint blockTime);
  event LM_CBClearQueuedStrikes(address indexed caller, uint indexed boardId);

  event LM_QueuedBoardStale(address indexed caller, uint indexed expiry, uint staleTimestamp, uint blockTime);
  event LM_CBClearQueuedBoard(address indexed caller, uint indexed expiry);

  ////////////
  // Errors //
  ////////////

  error LM_ExpiryExists(uint expiry);

  error LM_OnlyRiskCouncil(address sender);

  error LM_TooEarlyToExecuteStrike(uint boardId, uint queuedTime, uint blockTime);

  error LM_BoardStale(uint expiry, uint staleTime, uint blockTime);

  error LM_TooEarlyToExecuteBoard(uint expiry, uint queuedTime, uint blockTime);

  error LM_CBActive(uint blockTime);

  error LM_TooCloseToExpiry(uint expiry, uint boardId);

  error LM_BoardAlreadyQueued(uint expiry);

  error LM_ExpiryDoesntMatchFormat(uint expiry);

  error LM_ExpiryTooShort(uint expiry, uint minExpiry);

  error LM_NoBoards();

  error LM_NoNewStrikesGenerated(uint boardId);

  error LM_strikesAlreadyQueued(uint boardId);
}
