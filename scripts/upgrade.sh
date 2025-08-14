#!/bin/bash

set -euo pipefail

XIOND_FROM="facuet-dev"
XIOND_OPTS=(-y --from ${XIOND_FROM} --gas auto --gas-prices 0.001uxion --gas-adjustment 2.5 --chain-id xion-devnet-1 --node http://localhost:26657)

xiond tx staking delegate xionvaloper1prhv0yu0psgmn3vlcz0tlrxjvrqm340da9gjpm 100000000uxion ${XIOND_OPTS[@]}
sleep 2
xiond tx staking delegate xionvaloper18ssjr74xas33fgxz4e6xvkk3w72s672de25ety 100000000uxion ${XIOND_OPTS[@]}
sleep 2
xiond tx staking delegate xionvaloper132qm6589kwd6u9v75w70t4aw4pkehw5uvyq6hr 100000000uxion ${XIOND_OPTS[@]}
sleep 2
xiond tx gov submit-proposal proposals/upgrade.json ${XIOND_OPTS}
sleep 2
xiond tx gov vote 1 yes ${XIOND_OPTS}
