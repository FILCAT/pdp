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
echo "Creating contract"
forge create --rpc-url "$RPC_URL" --keystore "$KEYSTORE" --password "$PASSWORD" --compiler-version 0.8.20 --chain-id 31415926 contracts/src/PDPService.sol:PDPService --constructor-args 3
