#! /bin/bash
# deploy-devnet deploys the PDP service contract and all auxillary contracts to a filecoin devnet
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, jq are in the PATH
#
echo "Deploying to calibnet"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

echo "Deploying PDP service implementation"
# Parse the output of forge create to extract the contract address
IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 314159 src/PDPService.sol:PDPService | grep "Deployed to" | awk '{print $3}')

if [ -z "$IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract PDP service contract address"
    exit 1
fi
echo "PDP service implementation deployed at: $IMPLEMENTATION_ADDRESS"

echo "Deploying PDP service proxy"
INIT_DATA=$(cast calldata "initialize(uint256)" 3)
PDP_SERVICE_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 314159 src/ERC1967Proxy.sol:MyERC1967Proxy --constructor-args $IMPLEMENTATION_ADDRESS $INIT_DATA | grep "Deployed to" | awk '{print $3}')

echo "PDP service deployed at: $PDP_SERVICE_ADDRESS"

# Deploy PDP Record keeper 
echo "Deploying record keeper"
forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 314159 src/PDPRecordKeeper.sol:PDPRecordKeeper --constructor-args $PDP_SERVICE_ADDRESS
