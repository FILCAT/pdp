// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

contract PDPService is Ownable {
    // Types 

    // State fields
    uint256 public challengeFinality;

    // Methods
    constructor(uint256 _challengePeriod) Ownable(msg.sender) {
        challengePeriod = _challengePeriod;
    }

}