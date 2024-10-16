#! /bin/bash
# deploy-devnet deploys the PDP verifier and PDP service contracts to calibration net
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

echo "Deploying PDP verifier"
# Parse the output of forge create to extract the contract address
PDP_VERIFIER_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 314159 contracts/src/PDPVerifier.sol:PDPVerifier --constructor-args 3 | grep "Deployed to" | awk '{print $3}')

if [ -z "$IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract PDP service contract address"
    exit 1
fi
echo "PDP service implementation deployed at: $IMPLEMENTATION_ADDRESS"

echo "Deploying PDP service proxy"
INIT_DATA=$(cast calldata "initialize(uint256)" 3)
PDP_SERVICE_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 314159 src/ERC1967Proxy.sol:MyERC1967Proxy --constructor-args $IMPLEMENTATION_ADDRESS $INIT_DATA | grep "Deployed to" | awk '{print $3}')

echo "PDP verifier deployed at: $PDP_VERIFIER_ADDRESS"

echo "Deploying PDP Service"
forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 314159 contracts/src/SimplePDPService.sol:SimplePDPService --constructor-args $PDP_VERIFIER_ADDRESS
