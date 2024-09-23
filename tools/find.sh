#! /bin/bash

findCallData=$(cast calldata "findRootIds(uint256,uint256[])((uint256,uint256)[])" $2 $3)
cast send --keystore $KEYSTORE --password "$PASSWORD" --rpc-url $RPC_URL $1 $findCallData
