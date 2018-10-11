# Liquidity Random Game

This is a change game written in Liquidity. The user chooses a number
n between 0 and 100 and places a bet b on the smart contract. A random
number is picked by an oracle, if the random number is greater or
equal to n then the user is payer b + (b * n / 100).

The greater the number n is, the greater the risk and so the greater
the reward. However, this is not a fair game: the user is guaranteed
to lose money in the long run.

## Requirements

To deploy the contract and run the random generator server, you need
the following.

- liquidity installed on your system (in the path)
- tezos-client
- these opam packages: lwt, ocurl, ezjsonm

## Configuration

You can edit the `config.json` file, with the fields:
- `node`: an http address (and optionally port) of a running tezos node
- `private_key` : a private key for the server to sign random numbers
  (transactions)
  
## Deploying the contract

You will need the public key `<trusted_pk>` corresponding the previous
private key, as well as an account `<my_account>` in your
tezos-client.

First compile the contract (if it is not already compiled):
```
liquidity contracts/game.liq
```

Then deploy with the provided script:
```
contracts/deploy.sh "$HOME/dev/tezos/tezos-client -A zeronet-node.tzscan.io -P 80" <my_account> <manager> <trusted_pk>
```

This will deploy the contract on the blockchain which the client/node
knows and fill in the the parameters in the `config.json` file.

## Building and running the server

To build, simply issue
```
make
```

Once you have deployed the contract and built the server, the only
thing you need to do is to run
```
_obuild/liqgame-crawler/liqgame-crawler.asm
```

The server monitors the contract, and sends random numbers to said
contract to finish the game. The user is then paid accordingly.

In the output of the server, you will see messages with:
- block numbers
- game started such as `tz1WWXeGFgtARRLPPzT2qcpeiQZ8oQb6rBZd played 12`
- Random numbers sent to the contract by Liquidity, like
  `LIQUIDITY: liquidity --private-key
  edsk3Pjh28uJj2WS9F6zp6qfBXukbgAtggoovjZAsA6ic1sgnv6E9N --tezos-node
  http://zeronet-node.tzscan.io --fee 0tz contracts/game.liq --call
  KT1N61Q65h4t2BRXGRjQfMGBtEx3Pm8upV3s finish 62p`
- Game results: `Finishing game with random number 62`
- Funds added
