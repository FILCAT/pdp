// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

library PDPFees {

    // Estimate of USD price in FIL
    uint256 constant FIL_USD_NUM = 10;
    uint256 constant FIL_USD_DENOM = 35;
           
    uint256 constant ONE_PERCENT_DENOM = 100;

    uint256 constant LEAVES_PER_TIB = 2^35;

    uint256 constant EPOCHS_PER_MONTH = 86_400;
    // Revenue in usd per TiB per month
    uint256 constant MONTHLY_TIB_REVENUE_USD_NUM = 35;
    uint256 constant MONTHLY_TIB_REVENUE_USD_DENOM = 10;

    uint256 constant PROOF_GAS_FLOOR = 2_000_000;
    uint256 constant ONE_NANO_FIL = 10^9;
    uint256 constant ONE_FIL = 10^18;

    uint256 constant SYBIL_FEE = 10^17;

    // Currently unused
    //
    // Returns the service fee for a given proofset duration, and size
    // Size measured in leaves (32 byte chunks), duration measured in epochs
    function serviceFee(uint256 duration, uint256 size) internal pure returns (uint256) {
        // 1 FIL / TiB / month ~ revenue 
        // 86,400 epochs / month
        // 2^35 leafs / TiB
        // fee is 1% of revenue

        // [(Monthly revenue in USD) * (FIL / USD) * size * duration] / 
        // [Leaves per TiB * Epochs per month * 1%]
        uint256 numerator = ONE_FIL * MONTHLY_TIB_REVENUE_USD_NUM * FIL_USD_NUM * size * duration;
        uint256 denominator = MONTHLY_TIB_REVENUE_USD_DENOM * FIL_USD_DENOM * LEAVES_PER_TIB * EPOCHS_PER_MONTH * ONE_PERCENT_DENOM;
        return numerator / denominator;
    }

    // Returns the proof fee for a given challenge count
    function proofFee(uint256 challengeCount) internal view returns (uint256) {
        uint256 gasPrice;
        if (block.basefee > ONE_NANO_FIL) {
            gasPrice = block.basefee;
        } else {
            gasPrice = ONE_NANO_FIL;
        }
        uint256 numerator = PROOF_GAS_FLOOR * challengeCount * gasPrice;
        uint256 denominator = ONE_PERCENT_DENOM;
        return numerator / denominator;
    }

    // sybil fee adds cost to adding state to the pdp verifier contract to prevent 
    // wasteful state growth. 0.1 FIL
    function sybilFee() internal pure returns (uint256) {
        return SYBIL_FEE;
    }
}
