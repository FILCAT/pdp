#! /bin/bash
# deploy-devnet deploys the PDP service contract and all auxillary contracts to a filecoin devnet
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, lotus, jq are in the PATH
#
echo "Deploying to devnet"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

# Send funds from default to keystore address
# assumes lotus binary in path
clientAddr=$(cat $KEYSTORE | jq '.address' | sed -e 's/\"//g')
echo "Sending funds to $clientAddr"
lotus send $clientAddr 10000

# Deploy PDP service contract
echo "Deploying PDP service"
# Parse the output of forge create to extract the contract address
PDP_VERIFIER_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 31415926 contracts/src/PDPVerifier.sol:PDPVerifier --constructor-args 3 | grep "Deployed to" | awk '{print $3}')

if [ -z "$PDP_VERIFIER_ADDRESS" ]; then
    echo "Error: Failed to extract PDP verifier contract address"
    exit 1
fi

echo "PDP service deployed at: $PDP_VERIFIER_ADDRESS"

# Deploy PDP Record keeper 
echo "Deploying PDP Service"
forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 31415926 contracts/src/SimplePDPService.sol:SimplePDPService --constructor-args $PDP_VERIFIER_ADDRESS
