#! /bin/bash
# deploy-devnet deploys the PDP service contract and all auxillary contracts to a filecoin devnet
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, jq are in the PATH
#
echo "Deploying PDP service to calibration"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

# Deploy PDP service contract
echo "Deploying PDP service"
# Parse the output of forge create to extract the contract address
PDP_SERVICE_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 314159 contracts/src/PDPService.sol:PDPService --constructor-args 3 | grep "Deployed to" | awk '{print $3}')

if [ -z "$PDP_SERVICE_ADDRESS" ]; then
    echo "Error: Failed to extract PDP service contract address"
    exit 1
fi

echo "PDP service deployed at: $PDP_SERVICE_ADDRESS"

# Deploy PDP Record keeper 
echo "Deploying record keeper"
forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 314159 contracts/src/PDPRecordKeeper.sol:PDPRecordKeeper --constructor-args $PDP_SERVICE_ADDRESS
