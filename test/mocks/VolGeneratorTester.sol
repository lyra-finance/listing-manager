//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

import "src/lib/VolGenerator.sol";

contract VolGeneratorTester {
  function getSkewForNewBoard(
    uint newStrike,
    uint tTarget,
    uint baseIv,
    VolGenerator.Board memory shortDatedBoard,
    VolGenerator.Board memory longDatedBoard
  ) external view returns (uint newSkew) {
    return VolGenerator.getSkewForNewBoard(newStrike, tTarget, baseIv, shortDatedBoard, longDatedBoard);
  }

  function getSkewForNewBoard(
    uint newStrike,
    uint tTarget,
    uint baseIv,
    uint spot,
    VolGenerator.Board memory edgeBoard
  ) external view returns (uint newSkew) {
    return VolGenerator.getSkewForNewBoard(newStrike, tTarget, baseIv, spot, edgeBoard);
  }

  function getSkewForLiveBoard(
    uint newStrike,
    VolGenerator.Board memory liveBoard
  ) external view returns (uint newSkew) {
    return VolGenerator.getSkewForLiveBoard(newStrike, liveBoard);
  }
}
