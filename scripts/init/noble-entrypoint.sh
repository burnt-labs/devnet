#!/usr/bin/env bash
set -euo pipefail

# Noble single-validator init script for devnet
# Includes USDC (fiat-tokenfactory) genesis configuration

CHAIN_ID="noble-devnet-1"
DAEMON_NAME="nobled"
DAEMON_HOME="${HOME}/.noble"
STAKING_DENOM="ustake"
GENESIS_AMOUNT="1000000000000"
GENTX_AMOUNT="500000000000"

# Noble devnet mnemonic — different from xion and osmosis
MNEMONIC="camp creek youth spend option clinic entry ice front myth dress analyst merge work art gate challenge horror search gap fashion blanket ivory critic"

# Relayer shared mnemonic (same across all chains for Hermes)
RELAYER_MNEMONIC="opinion chunk knowledge hospital nature adjust candy struggle grain lemon virtual trigger fiber promise phone jelly name attitude arrow daring assist fossil liberty strong"

init_noble() {
    if [ -f "${DAEMON_HOME}/config/genesis.json" ]; then
        echo "Chain already initialized, starting..."
        exec ${DAEMON_NAME} start --home "${DAEMON_HOME}"
    fi

    echo "Initializing Noble chain ${CHAIN_ID}..."
    ${DAEMON_NAME} init validator --chain-id "${CHAIN_ID}" --home "${DAEMON_HOME}" > /dev/null 2>&1

    # Create validator key from mnemonic
    echo "${MNEMONIC}" | ${DAEMON_NAME} keys add validator --keyring-backend test --recover --home "${DAEMON_HOME}" > /dev/null 2>&1
    VALADDR=$(${DAEMON_NAME} keys show validator -a --keyring-backend test --home "${DAEMON_HOME}")
    echo "Validator address: ${VALADDR}"

    # Create minter key (for USDC minting)
    ${DAEMON_NAME} keys add minter --keyring-backend test --home "${DAEMON_HOME}" > /dev/null 2>&1
    MINTER=$(${DAEMON_NAME} keys show minter -a --keyring-backend test --home "${DAEMON_HOME}")
    echo "Minter address: ${MINTER}"

    # Create relayer key from shared mnemonic
    echo "${RELAYER_MNEMONIC}" | ${DAEMON_NAME} keys add relayer --keyring-backend test --recover --home "${DAEMON_HOME}" > /dev/null 2>&1
    RELAYADDR=$(${DAEMON_NAME} keys show relayer -a --keyring-backend test --home "${DAEMON_HOME}")
    echo "Relayer address: ${RELAYADDR}"

    # Fund accounts (staking denom)
    ${DAEMON_NAME} genesis add-genesis-account "${VALADDR}" "${GENESIS_AMOUNT}${STAKING_DENOM}" --home "${DAEMON_HOME}" --keyring-backend test
    ${DAEMON_NAME} genesis add-genesis-account "${MINTER}" "1000000${STAKING_DENOM}" --home "${DAEMON_HOME}" --keyring-backend test
    ${DAEMON_NAME} genesis add-genesis-account "${RELAYADDR}" "10000000000${STAKING_DENOM}" --home "${DAEMON_HOME}" --keyring-backend test

    # Create gentx
    ${DAEMON_NAME} genesis gentx validator "${GENTX_AMOUNT}${STAKING_DENOM}" \
        --chain-id "${CHAIN_ID}" \
        --keyring-backend test \
        --home "${DAEMON_HOME}"

    # Collect gentxs
    ${DAEMON_NAME} genesis collect-gentxs --home "${DAEMON_HOME}" > /dev/null 2>&1

    # ── Noble-specific genesis modifications (USDC / fiat-tokenfactory) ──

    GENESIS="${DAEMON_HOME}/config/genesis.json"
    TMP="/tmp/genesis_tmp.json"

    # Set staking bond denom
    jq '.app_state.staking.params.bond_denom = "ustake"' "${GENESIS}" > "${TMP}" && mv "${TMP}" "${GENESIS}"

    # Set authority owner
    jq --arg addr "${VALADDR}" '.app_state.authority.owner = $addr' "${GENESIS}" > "${TMP}" && mv "${TMP}" "${GENESIS}"

    # USDC denom metadata
    jq '.app_state.bank.denom_metadata += [{
        "description": "Circle USD Coin",
        "denom_units": [
            {"denom": "uusdc", "exponent": 0, "aliases": ["microusdc"]},
            {"denom": "usdc", "exponent": 6}
        ],
        "base": "uusdc",
        "display": "usdc",
        "name": "Circle USD Coin",
        "symbol": "USDC"
    }]' "${GENESIS}" > "${TMP}" && mv "${TMP}" "${GENESIS}"

    # Fiat token factory — enable USDC minting
    jq '.app_state["fiat-tokenfactory"].mintingDenom = {"denom": "uusdc"}' "${GENESIS}" > "${TMP}" && mv "${TMP}" "${GENESIS}"
    jq '.app_state["fiat-tokenfactory"].paused.paused = false' "${GENESIS}" > "${TMP}" && mv "${TMP}" "${GENESIS}"
    jq --arg addr "${VALADDR}" '.app_state["fiat-tokenfactory"].owner = {"address": $addr}' "${GENESIS}" > "${TMP}" && mv "${TMP}" "${GENESIS}"
    jq --arg addr "${VALADDR}" '.app_state["fiat-tokenfactory"].masterMinter = {"address": $addr}' "${GENESIS}" > "${TMP}" && mv "${TMP}" "${GENESIS}"
    jq --arg ctrl "${VALADDR}" --arg minter "${MINTER}" \
        '.app_state["fiat-tokenfactory"].minterControllerList = [{"controller": $ctrl, "minter": $minter}]' \
        "${GENESIS}" > "${TMP}" && mv "${TMP}" "${GENESIS}"
    jq --arg minter "${MINTER}" \
        '.app_state["fiat-tokenfactory"].mintersList = [{"address": $minter, "allowance": {"denom": "uusdc", "amount": "1000000000000000"}}]' \
        "${GENESIS}" > "${TMP}" && mv "${TMP}" "${GENESIS}"

    # Replace "stake" with "ustake" in genesis (Noble default denom fix)
    sed -i 's/"stake"/"ustake"/g' "${GENESIS}"

    # ── Config modifications ──

    CONFIG="${DAEMON_HOME}/config/config.toml"
    APP_CONFIG="${DAEMON_HOME}/config/app.toml"

    # Fast block times
    sed -i 's/^timeout_commit =.*$/timeout_commit = "1s"/' "${CONFIG}"
    sed -i 's/^timeout_propose =.*$/timeout_propose = "1s"/' "${CONFIG}"

    # Allow external RPC connections
    sed -i 's|laddr = "tcp://127.0.0.1:26657"|laddr = "tcp://0.0.0.0:26657"|' "${CONFIG}"

    # CORS
    sed -i 's/cors_allowed_origins = \[\]/cors_allowed_origins = ["*"]/' "${CONFIG}"

    # Disable strict address book
    sed -i 's/^addr_book_strict =.*$/addr_book_strict = false/' "${CONFIG}"

    # Enable API
    sed -i '/^\[api\]$/,/^\[/ s/^enable = false/enable = true/' "${APP_CONFIG}"
    sed -i 's|address = "tcp://localhost:1317"|address = "tcp://0.0.0.0:1317"|' "${APP_CONFIG}"

    # Enable gRPC
    sed -i '/^\[grpc\]$/,/^\[/ s/^enable = false/enable = true/' "${APP_CONFIG}"
    sed -i 's|address = "localhost:9090"|address = "0.0.0.0:9090"|' "${APP_CONFIG}"

    echo "Noble chain initialized successfully!"

    # Start chain, then mint USDC in background after chain is ready
    mint_usdc_background &
    exec ${DAEMON_NAME} start --home "${DAEMON_HOME}"
}

mint_usdc_background() {
    echo "Waiting for chain to produce blocks before minting USDC..."
    sleep 15
    for i in $(seq 1 30); do
        if ${DAEMON_NAME} status --home "${DAEMON_HOME}" 2>/dev/null | jq -e '.sync_info.latest_block_height | tonumber > 1' > /dev/null 2>&1; then
            echo "Chain is producing blocks, minting USDC..."
            ${DAEMON_NAME} tx fiat-tokenfactory mint "${MINTER}" 1000000000000uusdc \
                --from minter \
                --keyring-backend test \
                --home "${DAEMON_HOME}" \
                --chain-id "${CHAIN_ID}" \
                --gas auto \
                --gas-adjustment 1.5 \
                -y 2>&1 || echo "USDC mint failed, may need manual minting"
            return
        fi
        sleep 5
    done
    echo "WARNING: Chain did not produce blocks in time, USDC not minted"
}

# Export MINTER for background function
export MINTER=""
init_noble
