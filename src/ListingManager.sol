//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "../lib/lyra-protocol/contracts/libraries/Math.sol";
import "../lib/lyra-protocol/contracts/synthetix/DecimalMath.sol";

import "./TODO_CLEANUP_Interfaces.sol";

import "forge-std/console.sol";
import "./LastFridays.sol";

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
    uint cachedDelta;
    uint skew;
  }

  ILyraRegistry registry;

  uint MAX_SPOT_DIFF = 0.05e18;
  uint MAX_TIME_DIFF = 3 hours;

  constructor(ILyraRegistry _registry) {
    registry = _registry;
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

  function findAndQueueStrikesForBoard(uint boardId) external {
    // given no strikes queued for the board currently (and also check things like CBs in the liquidity pool)
    // for the given board, see if any strikes can be added based on the schema
    // if so; request the skews from the libraries
    // and then add to queue

    // Note: should be blocked when circuit breakers are firing

    // TODO: fetch data from newport contracts, fit into the format needed for the library and generate output/queue
  }

  function findAndQueueNewBoard() external {
    // TODO: Figure out if any expiry is missing from our structure/within a max expiry
    // info in keynote presentation - basically need to hardcode monthly expiries for the next 10-20 years - then have
    // a process for adding weekly expiries up to 10-12 weeks

    // Note: should be blocked when circuit breakers are firing

    // TODO: fetch data from newport contracts, fit into the format needed for the library and generate output/queue
  }

  function executeQueuedStrikes(uint boardId) external {
    // Note: should be blocked (probably actually just reverted?) when circuit breakers are firing
  }
  function executeQueuedBoard(uint expiry) external {
    // Note: should be blocked (probably actually just reverted?) when circuit breakers are firing
  }

  /////////////////////////
  /////////////////////////
  ////                 ////
  ////  Old doodlings  ////
  ////                 ////
  /////////////////////////
  /////////////////////////

  function getStrikesToAdd(address market, uint boardId) external view returns (uint[] memory) {
    IBaseExchangeAdapter exchangeAdapter = IBaseExchangeAdapter(registry.getGlobalAddress(bytes32("EXCHANGE_ADAPTER")));
    ILyraRegistry.OptionMarketAddresses memory marketAddresses = registry.getMarketAddresses(market);
    IOptionGreekCache greekCache = IOptionGreekCache(marketAddresses.greekCache);

    // we will trust the last cached greeks here, so revert if they are too stale
    IOptionGreekCache.OptionBoardCache memory boardCache = greekCache.getOptionBoardCache(boardId);
    if (block.timestamp - boardCache.updatedAt > MAX_TIME_DIFF) {
      revert("Cache update time is stale");
    }
    uint spotPrice = exchangeAdapter.getSpotPriceForMarket(market, IBaseExchangeAdapter.PriceType.REFERENCE);
    if (Math.abs(int(spotPrice) - int(boardCache.updatedAtPrice)).divideDecimal(spotPrice) > MAX_SPOT_DIFF) {
      revert("Cache spot update price is stale");
    }

    uint[] memory res = new uint[](1);
    res[0] = 420;
    return res;
  }

  function getSortedBoardDetails(IOptionMarket market, IOptionGreekCache greekCache, uint boardId)
    public
    returns (BoardDetails memory)
  {
    (IOptionMarket.OptionBoard memory board, IOptionMarket.Strike[] memory boardStrikes,, uint priceAtExpiry,) =
      market.getBoardAndStrikeDetails(boardId);
    IOptionGreekCache.BoardGreeksView memory boardGreeksView = greekCache.getBoardGreeksView(boardId);

    BoardDetails memory res = BoardDetails({
      expiry: board.expiry,
      baseIv: boardGreeksView.ivGWAV,
      strikes: new StrikeDetails[](boardStrikes.length)
    });

    for (uint i = 0; i < boardStrikes.length; i++) {
      res.strikes[i] = StrikeDetails({
        strikePrice: boardStrikes[i].strikePrice,
        cachedDelta: uint(boardGreeksView.strikeGreeks[i].callDelta), //todo: safecast
        skew: boardGreeksView.skewGWAVs[i]
      });
    }

    quickSort(res.strikes, 0, int(res.strikes.length - 1));

    return res;
  }

  function quickSort(StrikeDetails[] memory arr, int left, int right) internal pure {
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
      quickSort(arr, left, j);
    }
    if (i < right) {
      quickSort(arr, i, right);
    }
  }
}
