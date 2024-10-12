// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RandomnessTest {
    // Address of the randomness precompile
    address constant RANDOMNESS_PRECOMPILE = 0xfE00000000000000000000000000000000000006;

    function getRandomness(uint64 epoch) public view returns (bytes32) {
        // Prepare the input data (epoch as a uint256)
        uint256 input = uint256(epoch);

        // Call the precompile
        (bool success, bytes memory result) = RANDOMNESS_PRECOMPILE.staticcall(abi.encodePacked(input));

        // Check if the call was successful
        require(success, "Randomness precompile call failed");

        // Decode and return the result
        return abi.decode(result, (bytes32));
    }

    function getLookbackRandomness(uint64 lookback) public view returns (bytes32) {
        return getRandomness(uint64(block.number) - lookback);
    }

    function getRawRandomness(uint64 epoch) public view returns (bool,bytes memory) {
        // Prepare the input data (epoch as a uint256)
        uint256 input = uint256(epoch);

        // Call the precompile
        return RANDOMNESS_PRECOMPILE.staticcall(abi.encodePacked(input));
    }
}