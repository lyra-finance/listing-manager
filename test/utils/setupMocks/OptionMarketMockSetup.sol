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

  IOptionGreekCache.StrikeGreeks internal DEFAULT_STRIKE_GREEKS_1 =
    IOptionGreekCache.StrikeGreeks({callDelta: 0.1 ether, putDelta: -0.9 ether, stdVega: 0, callPrice: 0, putPrice: 0});
  IOptionGreekCache.StrikeGreeks internal DEFAULT_STRIKE_GREEKS_2 =
    IOptionGreekCache.StrikeGreeks({callDelta: 0.3 ether, putDelta: -0.6 ether, stdVega: 0, callPrice: 0, putPrice: 0});
  IOptionGreekCache.StrikeGreeks internal DEFAULT_STRIKE_GREEKS_3 =
    IOptionGreekCache.StrikeGreeks({callDelta: 0.5 ether, putDelta: -0.5 ether, stdVega: 0, callPrice: 0, putPrice: 0});
  IOptionGreekCache.StrikeGreeks internal DEFAULT_STRIKE_GREEKS_4 =
    IOptionGreekCache.StrikeGreeks({callDelta: 0.9 ether, putDelta: -0.1 ether, stdVega: 0, callPrice: 0, putPrice: 0});
  IOptionGreekCache.StrikeGreeks internal DEFAULT_STRIKE_GREEKS_5 =
    IOptionGreekCache.StrikeGreeks({callDelta: 0.8 ether, putDelta: -0.2 ether, stdVega: 0, callPrice: 0, putPrice: 0});

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

    uint[] memory strikeToBaseReturnedRatios = new uint[](5);

    IOptionMarket.Strike[] memory boardStrikes = new IOptionMarket.Strike[](5);
    boardStrikes[0] = DEFAULT_STRIKE_1;
    boardStrikes[1] = DEFAULT_STRIKE_2;
    boardStrikes[2] = DEFAULT_STRIKE_3;
    boardStrikes[3] = DEFAULT_STRIKE_4;
    boardStrikes[4] = DEFAULT_STRIKE_5;

    uint[] memory liveBoards = new uint[](1);
    liveBoards[0] = 1;

    vm.mockCall(
      address(optionMarket), abi.encodeWithSelector(IOptionMarket.getLiveBoards.selector), abi.encode(liveBoards)
    );

    vm.mockCall(
      address(optionMarket),
      abi.encodeWithSelector(IOptionMarket.getBoardAndStrikeDetails.selector),
      abi.encode(
        IOptionMarket.OptionBoard({
          id: 1,
          expiry: block.timestamp + 1 weeks,
          iv: 1 ether,
          frozen: false,
          strikeIds: strikeIds
        }),
        boardStrikes,
        strikeToBaseReturnedRatios,
        0,
        1 ether
      )
    );

    IOptionGreekCache.StrikeGreeks[] memory strikeGreeks = new IOptionGreekCache.StrikeGreeks[](5);
    strikeGreeks[0] = DEFAULT_STRIKE_GREEKS_1;
    strikeGreeks[1] = DEFAULT_STRIKE_GREEKS_2;
    strikeGreeks[2] = DEFAULT_STRIKE_GREEKS_3;
    strikeGreeks[3] = DEFAULT_STRIKE_GREEKS_4;
    strikeGreeks[4] = DEFAULT_STRIKE_GREEKS_5;

    vm.mockCall(
      address(greekCache),
      abi.encodeWithSelector(IOptionGreekCache.getBoardGreeksView.selector),
      abi.encode(
        IOptionGreekCache.BoardGreeksView({
          boardGreeks: IOptionGreekCache.NetGreeks({netDelta: 0, netStdVega: 0, netOptionValue: 0}),
          ivGWAV: 1 ether,
          strikeGreeks: strikeGreeks,
          skewGWAVs: skewGWAVs
        })
      )
    );
  }
}
