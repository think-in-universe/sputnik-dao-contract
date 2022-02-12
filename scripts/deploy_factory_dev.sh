#!/bin/bash
# This file is used for starting a fresh set of all contracts & configs
set -e

if [ -d "res" ]; then
  echo ""
else
  mkdir res
fi

cd "`dirname $0`"

if [ -z "$KEEP_NAMES" ]; then
  export RUSTFLAGS='-C link-arg=-s'
else
  export RUSTFLAGS=''
fi

# TODO: Change to the official approved commit:
COMMIT_V3=596f27a649c5df3310e945a37a41a957492c0322
git checkout $COMMIT_V3

# build the things
cargo build --all --target wasm32-unknown-unknown --release
cp ../target/wasm32-unknown-unknown/release/*.wasm ../res/

export NEAR_ENV=testnet
export FACTORY=testnet

if [ -z ${NEAR_ACCT+x} ]; then
  export NEAR_ACCT=sputnikv2.$FACTORY
else
  export NEAR_ACCT=$NEAR_ACCT
fi

export FACTORY_ACCOUNT_ID=$NEAR_ACCT
export DAO_ACCOUNT_ID=genesis.$FACTORY_ACCOUNT_ID
GAS_100_TGAS=100000000000000
GAS_150_TGAS=150000000000000

# Deploy factory contract
near deploy --wasmFile ../sputnikdao-factory2/res/sputnikdao_factory2.wasm --accountId $FACTORY_ACCOUNT_ID --initFunction new --initArgs '{}'

# Quick sanity check on getters
near view $FACTORY_ACCOUNT_ID get_dao_list

# Grab the contract v2 code data
http --json post https://rpc.testnet.near.org jsonrpc=2.0 id=dontcare method=query \
params:='{"request_type":"view_code","finality":"final","account_id":"'$DAO_ACCOUNT_ID'"}' \
| jq -r .result.code_base64 \
| base64 --decode > sputnikdao2_dev_code.wasm

# Store the code data
BYTES='cat sputnikdao2_dev_code.wasm | base64 -w 0'

# ----

# Update the factory metadata
# TODO: Get the response code hash!
V2_CODE_HASH=ZGdM2TFdQpcXrxPxvq25514EViyi9xBSboetDiB3Uiq
near call $FACTORY_ACCOUNT_ID store_contract_metadata '{"code_hash": "'$V2_CODE_HASH'", "metadata": {"version": [2,0], "commit_id": "c2cf1553b070d04eed8f659571440b27d398c588"}, "set_default": true}' --accountId $FACTORY_ACCOUNT_ID

# Sanity check the new metadata
near view $FACTORY_ACCOUNT_ID get_contracts_metadata

# Create V3 code & metadata
V3_BYTES='cat sputnikdao2/res/sputnikdao2.wasm | base64 -w 0'
near call $FACTORY_ACCOUNT_ID store $(eval "$V3_BYTES") --base64 --accountId $FACTORY_ACCOUNT_ID --gas $GAS_100_TGAS --amount 10
# TODO: Get the response code hash!
V2_CODE_HASH=GUMFKZP6kdLgy3NjKy1EAkn77AfZFLKkj96VAgjmHXeS
near call $FACTORY_ACCOUNT_ID store_contract_metadata '{"code_hash": "'$V3_CODE_HASH'", "metadata": {"version": [3,0], "commit_id": "'$COMMIT_V3'"}, "set_default": true}' --accountId $FACTORY_ACCOUNT_ID

# Sanity check the new metadata
near view $FACTORY_ACCOUNT_ID get_contracts_metadata

# ----

# Create a new DAO, Change council to what you own
COUNCIL='["test.testnet"]'
TIMESTAMP=$(date +"%s")
DAO_NAME=sputnikdao-dev-$TIMESTAMP
DAO_ARGS=`echo '{"config": {"name": "'$DAO_NAME'", "purpose": "Sputnik Dev DAO '$TIMESTAMP'", "metadata":""}, "policy": '$COUNCIL'}' | base64 -w 0`
near call $FACTORY_ACCOUNT_ID create "{\"name\": \"$DAO_NAME\", \"args\": \"$DAO_ARGS\"}" --accountId $FACTORY_ACCOUNT_ID --gas $GAS_150_TGAS --amount 10

# Sanity check all worked
near view $FACTORY_ACCOUNT_ID get_dao_list
near view $DAO_NAME.$FACTORY_ACCOUNT_ID get_available_amount

echo "Dev Factory Deploy & Test Complete"