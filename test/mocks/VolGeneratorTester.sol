// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "src/lib/VolGenerator.sol";

contract VolGeneratorTester {

  function getSkewForNewBoard(
    uint newStrike,
    uint tTarget,
    uint baseIv,
    VolGenerator.Board memory shortDatedBoard,
    VolGenerator.Board memory longDatedBoard
  ) external pure returns (uint newSkew) {
    return VolGenerator.getSkewForNewBoard(
      newStrike, tTarget, baseIv, shortDatedBoard, longDatedBoard
    );
  }

  function getSkewForNewBoard(
    uint newStrike,
    uint tTarget,
    uint baseIv,
    uint spot,
    VolGenerator.Board memory edgeBoard
  ) external pure returns (uint newSkew) {
    return VolGenerator.getSkewForNewBoard(newStrike, tTarget, baseIv, spot, edgeBoard);
  }

  function getSkewForLiveBoard(
    uint newStrike, VolGenerator.Board memory liveBoard
  ) external pure returns (uint newSkew) {
    return VolGenerator.getSkewForLiveBoard(newStrike, liveBoard);
  }

}