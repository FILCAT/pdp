# Makefile for PDP Contracts

# Variables
ETH_RPC_URL ?= 
KEYSTORE_PATH ?= 
PASSWORD ?= 
CHALLENGE_FINALITY ?= 

# Targets
build:
	cd contracts && /home/runner/.config/.foundry/bin/forge build

test:
	cd contracts && /home/runner/.config/.foundry/bin/forge test

deploy:
	cd contracts && /home/runner/.config/.foundry/bin/forge create --rpc-url $(ETH_RPC_URL) --keystore $(KEYSTORE_PATH) --password $(PASSWORD) src/PDPService.sol:PDPService --constructor-args $(CHALLENGE_FINALITY)