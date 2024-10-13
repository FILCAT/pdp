#! /bin/bash
# deploy-devnet deploys the PDP service contract and all auxillary contracts to a filecoin devnet
# Assumption: KEYSTORE, PASSWORD, RPC_URL env vars are set to an appropriate eth keystore path and password
# and to a valid RPC_URL for the devnet.
# Assumption: forge, cast, jq are in the PATH
#
echo "Upgrading calibnet"

if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL is not set"
  exit 1
fi

if [ -z "$KEYSTORE" ]; then
  echo "Error: KEYSTORE is not set"
  exit 1
fi

if [ -z "$PDP_SERVICE_ADDRESS" ]; then
  echo "Error: PDP_SERVICE_ADDRESS is not set"
  exit 1
fi

if [ -z "$UPGRADE_DATA" ]; then
  echo "Error: UPGRADE_DATA is not set"
  exit 1
fi

echo "Deploying New PDP service implementation"
# Parse the output of forge create to extract the contract address
IMPLEMENTATION_ADDRESS=$(forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 314159 src/PDPService.sol:PDPService | grep "Deployed to" | awk '{print $3}')

if [ -z "$IMPLEMENTATION_ADDRESS" ]; then
    echo "Error: Failed to extract PDP service contract address"
    exit 1
fi
echo "PDP service implementation deployed at: $IMPLEMENTATION_ADDRESS"

echo "Upgrading PDP service proxy"
cast send --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --chain-id 314159 $PDP_SERVICE_ADDRESS "upgradeToAndCall(address,bytes)" $IMPLEMENTATION_ADDRESS $UPGRADE_DATA
