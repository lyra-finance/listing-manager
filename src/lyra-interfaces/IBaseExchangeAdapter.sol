//SPDX-License-Identifier: ISC
pragma solidity 0.8.16;

interface IBaseExchangeAdapter {
  enum PriceType {
    MIN_PRICE, // minimise the spot based on logic in adapter - can revert
    MAX_PRICE, // maximise the spot based on logic in adapter
    REFERENCE,
    FORCE_MIN, // minimise the spot based on logic in adapter - shouldn't revert unless feeds are compromised
    FORCE_MAX
  }

  function getSpotPriceForMarket(address, PriceType) external view returns (uint spot);
}
