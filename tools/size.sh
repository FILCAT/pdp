#!/bin/bash
# Usage: ./size.sh <contract-address> <proof-set-id>
# Returns the total number of root ids ever added to the proof set

# Check if required environment variables are set
if [ -z "$RPC_URL" ] || [ -z "$KEYSTORE" ]; then
    echo "Error: Please set RPC_URL, KEYSTORE, and PASSWORD environment variables."
    exit 1
fi

# Check if proof set ID is provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: <contract_address> <proof_set_id>"
    exit 1
fi

CONTRACT_ADDRESS=$1
PROOF_SET_ID=$2

# Create the calldata for getProofSetLeafCount(uint256)
CALLDATA=$(cast calldata "getNextRootId(uint256)" $PROOF_SET_ID)

# Call the contract and get the proof set size
PROOF_SET_SIZE=$(cast call --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $CONTRACT_ADDRESS $CALLDATA)
# Remove the "0x" prefix and convert the hexadecimal output to a decimal integer
PROOF_SET_SIZE=$(echo $PROOF_SET_SIZE | xargs printf "%d\n")

echo "Proof set size: $PROOF_SET_SIZE"