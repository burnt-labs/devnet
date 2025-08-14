#!/bin/sh

# Get host directory
: ${my_dir:="$(realpath $(dirname $0))"}
: ${base_dir:="$(dirname $my_dir)"}

# Prepare volume directory in HOME
mkdir -p ${HOME}/xiond-devnet
cp $my_dir/*json ${HOME}/xiond-devnet/
cp $my_dir/entrypoint.sh ${HOME}/xiond-devnet/

# This is provided as an example, adjust as needed
exec docker run \
  --rm \
  --workdir=/home/xiond \
  --volume=${base_dir}/.env:/home/xiond/.env \
  --volume=${base_dir}/scripts/init:/home/xiond/init \
  --entrypoint=/home/xiond/init/entrypoint.sh \
  --env="HOME=/home/xiond" \
  --env="SINGLETON=true" \
  --publish 1317:1317 \
  --publish 9090:9090 \
  --publish 26657:26657 \
  ghcr.io/burnt-labs/xion/xion:${XIOND_VERSION:-latest} cosmovisor run start
