#! /bin/bash
# Usage: ./remove.sh <contract-address> <proof-set-id> <input-list>
# input-list is a comma separated list of uint256s representing root ids to remove
removeCallData=$(cast calldata "removeRoots(uint256,uint256[])(uint256)" $2 $3)
cast send --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $1 $removeCallData
