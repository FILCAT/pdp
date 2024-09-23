#! /bin/bash

removeCallData=$(cast calldata "removeRoots(uint256,uint256[])(uint256)" $2 $3)
cast send --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $1 $removeCallData
