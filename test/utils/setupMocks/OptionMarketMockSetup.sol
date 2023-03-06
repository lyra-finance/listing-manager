//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../mocks/LyraContractMocks.sol";

contract OptionMarketMockSetup is Test {
  uint[5] internal DEFAULT_SKEW_GWAVS = [1.2 ether, 1.15 ether, 0.96 ether, 1.05 ether, 1.5 ether];
  IOptionMarket.Strike internal DEFAULT_STRIKE_1 = IOptionMarket.Strike({
    id: 1,
    strikePrice: 1200 ether,
    skew: 1.1 ether,
    longCall: 0,
    shortCallBase: 0,
    shortCallQuote: 0,
    longPut: 0,
    shortPut: 0,
    boardId: 1
  });
  IOptionMarket.Strike internal DEFAULT_STRIKE_2 = IOptionMarket.Strike({
    id: 2,
    strikePrice: 1300 ether,
    skew: 1.01 ether,
    longCall: 0,
    shortCallBase: 0,
    shortCallQuote: 0,
    longPut: 0,
    shortPut: 0,
    boardId: 1
  });
  IOptionMarket.Strike internal DEFAULT_STRIKE_3 = IOptionMarket.Strike({
    id: 3,
    strikePrice: 1500 ether,
    skew: 0.96 ether,
    longCall: 0,
    shortCallBase: 0,
    shortCallQuote: 0,
    longPut: 0,
    shortPut: 0,
    boardId: 1
  });
  IOptionMarket.Strike internal DEFAULT_STRIKE_4 = IOptionMarket.Strike({
    id: 4,
    strikePrice: 2100 ether,
    skew: 1.04 ether,
    longCall: 0,
    shortCallBase: 0,
    shortCallQuote: 0,
    longPut: 0,
    shortPut: 0,
    boardId: 1
  });
  IOptionMarket.Strike internal DEFAULT_STRIKE_5 = IOptionMarket.Strike({
    id: 5,
    strikePrice: 2000 ether,
    skew: 0.99 ether,
    longCall: 0,
    shortCallBase: 0,
    shortCallQuote: 0,
    longPut: 0,
    shortPut: 0,
    boardId: 1
  });

  function mockDefaultBoard(IOptionMarket optionMarket, IOptionGreekCache greekCache) public {
    uint[] memory strikeIds = new uint[](5);
    strikeIds[0] = DEFAULT_STRIKE_1.id;
    strikeIds[1] = DEFAULT_STRIKE_2.id;
    strikeIds[2] = DEFAULT_STRIKE_3.id;
    strikeIds[3] = DEFAULT_STRIKE_4.id;
    strikeIds[4] = DEFAULT_STRIKE_5.id;

    uint[] memory skewGWAVs = new uint[](5);
    skewGWAVs[0] = DEFAULT_SKEW_GWAVS[0];
    skewGWAVs[1] = DEFAULT_SKEW_GWAVS[1];
    skewGWAVs[2] = DEFAULT_SKEW_GWAVS[2];
    skewGWAVs[3] = DEFAULT_SKEW_GWAVS[3];
    skewGWAVs[4] = DEFAULT_SKEW_GWAVS[4];

    IOptionMarket.Strike[] memory boardStrikes = new IOptionMarket.Strike[](5);
    boardStrikes[0] = DEFAULT_STRIKE_1;
    boardStrikes[1] = DEFAULT_STRIKE_2;
    boardStrikes[2] = DEFAULT_STRIKE_3;
    boardStrikes[3] = DEFAULT_STRIKE_4;
    boardStrikes[4] = DEFAULT_STRIKE_5;

    uint[] memory liveBoards = new uint[](1);
    liveBoards[0] = 1;

    mockGetLiveBoards(optionMarket, liveBoards);

    mockGetBoardAndStrikeDetails(optionMarket, block.timestamp + 1 weeks, strikeIds, boardStrikes, 1 ether);

    mockGetBoardGreeksView(greekCache, skewGWAVs, 1 ether);
  }

  function mockBoardWithThreeStrikes(IOptionMarket optionMarket, IOptionGreekCache greekCache, uint expiry) public {
    uint[] memory strikePrices = new uint[](3);
    strikePrices[0] = DEFAULT_STRIKE_1.strikePrice;
    strikePrices[1] = DEFAULT_STRIKE_2.strikePrice;
    strikePrices[2] = DEFAULT_STRIKE_3.strikePrice;

    uint[] memory skewGWAVs = new uint[](3);
    skewGWAVs[0] = DEFAULT_STRIKE_1.skew;
    skewGWAVs[1] = DEFAULT_STRIKE_2.skew;
    skewGWAVs[2] = DEFAULT_STRIKE_3.skew;

    mockSingleBoard(optionMarket, greekCache, expiry, uint(1 ether), strikePrices, skewGWAVs);
  }

  function mockSingleBoard(
    IOptionMarket optionMarket,
    IOptionGreekCache greekCache,
    uint expiry,
    uint baseIv,
    uint[] memory strikePrices,
    uint[] memory skewGWAVs
  ) public {
    IOptionMarket.Strike[] memory boardStrikes = new IOptionMarket.Strike[](strikePrices.length);
    uint[] memory strikeIds = new uint[](strikePrices.length);
    for (uint i = 0; i < strikePrices.length; i++) {
      strikeIds[i] = i + 1;
      boardStrikes[i] = IOptionMarket.Strike({
        id: i + 1,
        strikePrice: strikePrices[i],
        skew: skewGWAVs[i],
        longCall: 0,
        shortCallBase: 0,
        shortCallQuote: 0,
        longPut: 0,
        shortPut: 0,
        boardId: 1
      });
    }

    uint[] memory liveBoards = new uint[](1);
    liveBoards[0] = 1;

    mockGetLiveBoards(optionMarket, liveBoards);

    mockGetBoardAndStrikeDetails(optionMarket, expiry, strikeIds, boardStrikes, baseIv);

    mockGetBoardGreeksView(greekCache, skewGWAVs, baseIv);
  }

  function mockBoardWithZeroStrikes(IOptionMarket optionMarket, IOptionGreekCache greekCache, uint expiry) public {
    uint[] memory strikeIds = new uint[](0);

    uint[] memory skewGWAVs = new uint[](0);

    IOptionMarket.Strike[] memory boardStrikes = new IOptionMarket.Strike[](0);

    uint[] memory liveBoards = new uint[](1);
    liveBoards[0] = 1;

    mockGetLiveBoards(optionMarket, liveBoards);

    mockGetBoardAndStrikeDetails(optionMarket, expiry, strikeIds, boardStrikes, 1 ether);

    mockGetBoardGreeksView(greekCache, skewGWAVs, 1 ether);
  }

  function mockGetBoardAndStrikeDetails(
    IOptionMarket optionMarket,
    uint expiry,
    uint[] memory strikeIds,
    IOptionMarket.Strike[] memory boardStrikes,
    uint baseIv
  ) public {
    if (strikeIds.length != boardStrikes.length) {
      revert("mockGetBoardAndStrikeDetails: strike length mismatch");
    }

    vm.mockCall(
      address(optionMarket),
      abi.encodeWithSelector(IOptionMarket.getBoardAndStrikeDetails.selector),
      abi.encode(
        IOptionMarket.OptionBoard({id: 1, expiry: expiry, iv: baseIv, frozen: false, strikeIds: strikeIds}),
        boardStrikes,
        new uint[](strikeIds.length),
        0,
        1 ether
      )
    );
  }

  function mockGetBoardGreeksView(IOptionGreekCache greekCache, uint[] memory skewGWAVs, uint ivGWAV) public {
    vm.mockCall(
      address(greekCache),
      abi.encodeWithSelector(IOptionGreekCache.getBoardGreeksView.selector),
      abi.encode(
        IOptionGreekCache.BoardGreeksView({
          boardGreeks: IOptionGreekCache.NetGreeks({netDelta: 0, netStdVega: 0, netOptionValue: 0}),
          ivGWAV: ivGWAV,
          strikeGreeks: new IOptionGreekCache.StrikeGreeks[](skewGWAVs.length),
          skewGWAVs: skewGWAVs
        })
      )
    );
  }

  function mockGetLiveBoards(IOptionMarket optionMarket, uint[] memory liveBoards) public {
    vm.mockCall(
      address(optionMarket), abi.encodeWithSelector(IOptionMarket.getLiveBoards.selector), abi.encode(liveBoards)
    );
  }
}
