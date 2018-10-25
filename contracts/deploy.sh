#!/bin/bash

set -e
set -o pipefail
# set -x

export TEZOS_CLIENT_UNSAFE_DISABLE_DISCLAIMER=Y

HERE=`dirname $0`
TEZOS_CLIENT=$1
TEZOS_ALIAS=$2
MANAGER=$3
AMOUNT=$4


TEZOS_NODE=$(cat $HERE/../config.json | jq -r ".node" | awk -F[/] '{print $3}')
TEZOS_ADDR=$(echo "$TEZOS_NODE" | awk -F[:] '{print $1}')
TEZOS_PORT=$(echo "$TEZOS_NODE" | awk -F[:] '{print $2}')
if [ -z "$TEZOS_PORT" ] ; then
    TEZOS_PORT="80"
fi
TEZOS_CLIENT="$TEZOS_CLIENT -A $TEZOS_ADDR -P $TEZOS_PORT"

TMP_NAME="TTTTTTTTTTTTTTTTTTTTT$RANDOM"
# $(cat /dev/urandom | tr -dc 'a-zA-Z' | fold -w 20 | head -n 1)
# echo $?
SERVER_SK=$(cat $HERE/../config.json | jq -r ".private_key")
SERVER_PK=$($TEZOS_CLIENT import secret key $TMP_NAME unencrypted:$SERVER_SK --force | grep "Tezos address"| cut -d " " -f 4)
$TEZOS_CLIENT forget address $TMP_NAME --force


INIT=$($TEZOS_CLIENT run script $HERE/game.liq.initializer.tz on storage "(Pair None \"$SERVER_PK\")" and input "\"$SERVER_PK\"" 2> /dev/null | grep storage -A 1 | tail -n 1)

echo "Initial storage : $INIT"

echo "Deploying liqgame contract"
$TEZOS_CLIENT -w 0 originate contract liqgame for $MANAGER \
              transferring $AMOUNT from $TEZOS_ALIAS \
              running $HERE/game.liq.tz \
              --fee 0 -q --force \
              --spendable \
              --delegatable \
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
# ./deploy.sh "$HOME/dev/tezos-zeronet/tezos-client" my_account my_account 1000
