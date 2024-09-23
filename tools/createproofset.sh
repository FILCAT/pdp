#! /bin/bash

#!/bin/bash

# Check if required environment variables are set
if [ -z "$RPC_URL" ] || [ -z "$KEYSTORE" ] ; then
    echo "Error: Please set RPC_URL, KEYSTORE, and PASSWORD environment variables."
    exit 1
fi

# Get the contract address from the command line argument
if [ -z "$1" ]; then
    echo "Usage: $0 <contract_address>"
    exit 1
fi

CONTRACT_ADDRESS=$1

# Create the calldata for createProofSet()
CALLDATA=$(cast calldata "createProofSet()(uint256)")

# Send the transaction
cast send --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $CONTRACT_ADDRESS $CALLDATA