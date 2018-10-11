#!/bin/bash

set -e
set -o pipefail

HERE=`dirname $0`
TEZOS_CLIENT=$1
TEZOS_ALIAS=$2
MANAGER=$3
SERVER=$4

# TEZOS_ALIAS="unencrypted:$(jq -r .private_key $HERE/../config.json)"

INIT=$($TEZOS_CLIENT run script $HERE/game.liq.initializer.tz on storage "(Pair None \"$SERVER\")" and input "\"$SERVER\"" 2> /dev/null | grep storage -A 1 | tail -n 1)

echo "Initial storage : $INIT"

echo "Deploying liqgame contract"
$TEZOS_CLIENT -w 0 originate contract liqgame for $MANAGER \
              transferring 1000 from $TEZOS_ALIAS \
              running $HERE/game.liq.tz \
              --fee 0 -q --force \
              --spendable \
              --init "$INIT" | tee /tmp/liqgamedeploy.log

CONTRACT=$(grep 'New contract' /tmp/liqgamedeploy.log \
               | sed -E 's/.*(KT1[a-zA-Z0-9]+).*/\1/' \
               | head -1)
BLOCK=$(grep 'Operation found in block' /tmp/liqgamedeploy.log \
               | sed -E 's/.*\b(B[a-zA-Z0-9]+)\b.*/\1/' \
               | head -1)

echo "Contract deployed at $CONTRACT in block $BLOCK"

echo "Contract deployed at $TR_CONTRACT"

echo "Modifying $(realpath $HERE/../config.json) accordingly"

cat $HERE/../config.json \
    | jq ".game_contract_hash = \"$CONTRACT\"" \
    | jq ".origination_block = \"$BLOCK\""  > $HERE/../config.tmp.json
mv -f $HERE/../config.tmp.json $HERE/../config.json

echo "Done."


# Example deployment:
# ./deploy.sh "$HOME/dev/tezos-zeronet/tezos-client -A http://zeronet-node.tzscan.io -P 80" my_account tz1NfNNPhwT6CHFRpaU89HR7pDQHAKj1gj1B
