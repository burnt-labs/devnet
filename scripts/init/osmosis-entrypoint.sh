#!/usr/bin/env bash
set -euo pipefail

# Osmosis single-validator init script for devnet
# Simplified from xion entrypoint.sh pattern

CHAIN_ID="localosmo-1"
DAEMON_NAME="osmosisd"
DAEMON_HOME="${HOME}/.osmosisd"
DEFAULT_DENOM="uosmo"
GENESIS_AMOUNT="1000000000000"
GENTX_AMOUNT="500000000000"

# Osmosis devnet mnemonic — different from xion
MNEMONIC="milk butter claim chair orient slow already effort champion feed meadow catalog worry kitchen risk flower surround cloud trip chapter vehicle economy voyage abstract"

# Relayer shared mnemonic (same across all chains for Hermes)
RELAYER_MNEMONIC="opinion chunk knowledge hospital nature adjust candy struggle grain lemon virtual trigger fiber promise phone jelly name attitude arrow daring assist fossil liberty strong"

init_osmosis() {
    if [ -f "${DAEMON_HOME}/config/genesis.json" ]; then
        echo "Chain already initialized, starting..."
        exec ${DAEMON_NAME} start --home "${DAEMON_HOME}"
    fi

    echo "Initializing Osmosis chain ${CHAIN_ID}..."
    ${DAEMON_NAME} init validator --chain-id "${CHAIN_ID}" --home "${DAEMON_HOME}" --default-denom "${DEFAULT_DENOM}" > /dev/null 2>&1

    # Create validator key from mnemonic
    echo "${MNEMONIC}" | ${DAEMON_NAME} keys add validator --keyring-backend test --recover --home "${DAEMON_HOME}" > /dev/null 2>&1
    VALADDR=$(${DAEMON_NAME} keys show validator -a --keyring-backend test --home "${DAEMON_HOME}")
    echo "Validator address: ${VALADDR}"

    # Create relayer key from shared mnemonic
    echo "${RELAYER_MNEMONIC}" | ${DAEMON_NAME} keys add relayer --keyring-backend test --recover --home "${DAEMON_HOME}" > /dev/null 2>&1
    RELAYADDR=$(${DAEMON_NAME} keys show relayer -a --keyring-backend test --home "${DAEMON_HOME}")
    echo "Relayer address: ${RELAYADDR}"

    # Create test account
    ${DAEMON_NAME} keys add test-account --keyring-backend test --home "${DAEMON_HOME}" > /dev/null 2>&1
    TESTADDR=$(${DAEMON_NAME} keys show test-account -a --keyring-backend test --home "${DAEMON_HOME}")

    # Fund accounts in genesis
    ${DAEMON_NAME} genesis add-genesis-account "${VALADDR}" "${GENESIS_AMOUNT}${DEFAULT_DENOM}" --home "${DAEMON_HOME}" --keyring-backend test
    ${DAEMON_NAME} genesis add-genesis-account "${RELAYADDR}" "10000000000${DEFAULT_DENOM}" --home "${DAEMON_HOME}" --keyring-backend test
    ${DAEMON_NAME} genesis add-genesis-account "${TESTADDR}" "10000000000${DEFAULT_DENOM}" --home "${DAEMON_HOME}" --keyring-backend test

    # Create gentx
    ${DAEMON_NAME} genesis gentx validator "${GENTX_AMOUNT}${DEFAULT_DENOM}" \
        --chain-id "${CHAIN_ID}" \
        --keyring-backend test \
        --home "${DAEMON_HOME}"

    # Collect gentxs
    ${DAEMON_NAME} genesis collect-gentxs --home "${DAEMON_HOME}" > /dev/null 2>&1

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

    echo "Osmosis chain initialized successfully!"
    exec ${DAEMON_NAME} start --home "${DAEMON_HOME}"
}

init_osmosis
