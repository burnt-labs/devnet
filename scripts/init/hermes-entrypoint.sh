#!/usr/bin/env bash
set -euo pipefail

# Hermes IBC relayer init script
# Waits for all chains, imports keys, creates clients/connections/channels, starts relaying

# Shared relayer mnemonic (same as in osmosis/noble entrypoints)
RELAYER_MNEMONIC="opinion chunk knowledge hospital nature adjust candy struggle grain lemon virtual trigger fiber promise phone jelly name attitude arrow daring assist fossil liberty strong"

HERMES_HOME="${HOME}/.hermes"
MNEMONIC_FILE="/tmp/relayer_mnemonic.txt"

echo "${RELAYER_MNEMONIC}" > "${MNEMONIC_FILE}"

# ── Wait for all chains to be healthy ──

wait_for_chain() {
    local name="$1"
    local rpc="$2"
    echo "Waiting for ${name} at ${rpc}..."
    for i in $(seq 1 120); do
        if curl -sf "${rpc}/status" > /dev/null 2>&1; then
            local height=$(curl -sf "${rpc}/status" | jq -r '.result.sync_info.latest_block_height // "0"')
            if [ "${height}" != "0" ] && [ "${height}" != "null" ] && [ "$(echo "${height}" | tr -d '[:space:]')" -gt 1 ] 2>/dev/null; then
                echo "${name} is ready (block height: ${height})"
                return 0
            fi
        fi
        sleep 5
    done
    echo "ERROR: ${name} did not become ready in time"
    exit 1
}

wait_for_chain "Xion"    "http://xion:26657"
wait_for_chain "Osmosis" "http://osmosis:26657"
wait_for_chain "Noble"   "http://noble:26657"

echo "All chains are healthy!"

# ── Import relayer keys ──

echo "Importing relayer keys..."
hermes keys add --chain xion-devnet-1    --mnemonic-file "${MNEMONIC_FILE}" --overwrite 2>&1 || true
hermes keys add --chain localosmo-1      --mnemonic-file "${MNEMONIC_FILE}" --overwrite 2>&1 || true
hermes keys add --chain noble-devnet-1   --mnemonic-file "${MNEMONIC_FILE}" --overwrite 2>&1 || true

rm -f "${MNEMONIC_FILE}"

# ── Create clients, connections, and channels ──

echo "Creating Xion ↔ Osmosis connection..."
hermes create client --host-chain xion-devnet-1 --reference-chain localosmo-1
hermes create client --host-chain localosmo-1 --reference-chain xion-devnet-1
hermes create connection --a-chain xion-devnet-1 --b-chain localosmo-1
echo "Creating Xion ↔ Osmosis transfer channel (connection-0)..."
hermes create channel --a-chain xion-devnet-1 --a-connection connection-0 --a-port transfer --b-port transfer

echo "Creating Xion ↔ Noble connection..."
hermes create client --host-chain xion-devnet-1 --reference-chain noble-devnet-1
hermes create client --host-chain noble-devnet-1 --reference-chain xion-devnet-1
hermes create connection --a-chain xion-devnet-1 --b-chain noble-devnet-1
echo "Creating Xion ↔ Noble transfer channel (connection-1)..."
hermes create channel --a-chain xion-devnet-1 --a-connection connection-1 --a-port transfer --b-port transfer

echo "IBC channels created successfully!"
echo "Starting Hermes relayer..."

exec hermes start
