#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════════════════
# deploy-contracts.sh — Post-genesis contract deployment for devnet
#
# Instantiates abstract account + treasury (fee granter) contracts after
# the chain starts producing blocks. The entrypoint.sh stores WASM codes
# in genesis (code_id 1 = abstract account, code_id 2 = treasury) but
# does NOT instantiate them. This script does the instantiation step.
#
# Usage: Run as a one-shot init container after xion is healthy.
#   docker compose run --rm deploy-contracts
# ═══════════════════════════════════════════════════════════════════════════

SCRIPTS_DIR=$(dirname "$0")

# Load environment
if [ -f "${HOME}/.env" ]; then
    source "${HOME}/.env"
fi

# Defaults
CHAIN_ID="${CHAIN_ID:-xion-devnet-1}"
DAEMON_NAME="${DAEMON_NAME:-xiond}"
DEFAULT_DENOM="${DEFAULT_DENOM:-uxion}"
NODE="${XION_RPC:-http://xion:26657}"
ABSTRAXION_KEY="abstraxion"

# The mnemonic is the same devnet mnemonic used in entrypoint.sh
MNEMONIC="${MNEMONIC:?MNEMONIC is required}"

OUTPUT_FILE="${OUTPUT_FILE:-/home/${DAEMON_NAME}/deploy-contracts.env}"

# ─── Helpers ──────────────────────────────────────────────────────────────

log() { echo "[deploy-contracts] $*"; }

wait_for_chain() {
    log "Waiting for chain to produce blocks..."
    local attempts=0
    while ! ${DAEMON_NAME} status --node "${NODE}" 2>/dev/null | jq -e '.sync_info.latest_block_height | tonumber > 1' > /dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [ $attempts -ge 120 ]; then
            log "ERROR: Chain not ready after 120s"
            exit 1
        fi
        sleep 1
    done
    log "Chain is producing blocks"
}

recover_key() {
    log "Recovering deployer key '${ABSTRAXION_KEY}'..."
    echo "${MNEMONIC}" | ${DAEMON_NAME} keys add "${ABSTRAXION_KEY}" \
        --account 1 --index 0 \
        --keyring-backend test --recover --output json 2>/dev/null || true
    DEPLOYER_ADDR=$(${DAEMON_NAME} keys show "${ABSTRAXION_KEY}" -a --keyring-backend test)
    log "Deployer address: ${DEPLOYER_ADDR}"
}

tx_flags() {
    echo "--from ${ABSTRAXION_KEY} --keyring-backend test --chain-id ${CHAIN_ID} --node ${NODE} --gas auto --gas-adjustment 1.5 --gas-prices 0.001${DEFAULT_DENOM} -y --output json"
}

wait_for_tx() {
    local txhash="$1"
    local attempts=0
    while ! ${DAEMON_NAME} query tx "${txhash}" --node "${NODE}" --output json 2>/dev/null | jq -e '.code == 0' > /dev/null 2>&1; do
        attempts=$((attempts + 1))
        if [ $attempts -ge 30 ]; then
            log "ERROR: tx ${txhash} not confirmed after 30s"
            ${DAEMON_NAME} query tx "${txhash}" --node "${NODE}" --output json 2>/dev/null || true
            exit 1
        fi
        sleep 1
    done
}

# ─── Contract Instantiation ──────────────────────────────────────────────

instantiate_abstract_account() {
    local code_id=1
    log "Instantiating abstract account contract (code_id=${code_id})..."

    local init_msg='{"account_owner":{"key":"Ag=="}}'

    local result
    result=$(${DAEMON_NAME} tx wasm instantiate "${code_id}" "${init_msg}" \
        --label "abstract-account-devnet" \
        --admin "${DEPLOYER_ADDR}" \
        $(tx_flags) 2>&1)

    local txhash
    txhash=$(echo "${result}" | jq -r '.txhash // empty')
    if [ -z "${txhash}" ]; then
        log "WARN: Abstract account instantiation may have failed: ${result}"
        AA_CONTRACT_ADDR=""
        return
    fi

    wait_for_tx "${txhash}"
    AA_CONTRACT_ADDR=$(${DAEMON_NAME} query tx "${txhash}" --node "${NODE}" --output json | \
        jq -r '.events[] | select(.type=="instantiate") | .attributes[] | select(.key=="_contract_address") | .value')
    log "Abstract account contract: ${AA_CONTRACT_ADDR}"
}

instantiate_treasury() {
    local code_id=2
    log "Instantiating treasury/fee-granter contract (code_id=${code_id})..."

    # Treasury instantiate msg based on e2e test patterns
    # This sets up a basic fee granter with common authz grants
    local init_msg
    init_msg=$(cat <<'EOF'
{
    "admin": null,
    "type_urls": [
        "/cosmos.bank.v1beta1.MsgSend",
        "/cosmwasm.wasm.v1.MsgExecuteContract"
    ],
    "grant_configs": [
        {
            "description": "Bank send authorization",
            "authorization": {
                "type_url": "/cosmos.authz.v1beta1.GenericAuthorization",
                "value": "CiEvY29zbW9zLmJhbmsudjFiZXRhMS5Nc2dTZW5k"
            },
            "optional": true
        },
        {
            "description": "Wasm execute authorization",
            "authorization": {
                "type_url": "/cosmos.authz.v1beta1.GenericAuthorization",
                "value": "CicvY29zbXdhc20ud2FzbS52MS5Nc2dFeGVjdXRlQ29udHJhY3Q="
            },
            "optional": true
        }
    ],
    "fee_config": {
        "description": "Devnet fee allowance",
        "allowance": {
            "type_url": "/cosmos.feegrant.v1beta1.BasicAllowance",
            "value": ""
        },
        "expiration": 31536000
    },
    "params": {
        "redirect_url": "http://localhost:4173",
        "icon_url": "https://xion.burnt.com/icon.png",
        "metadata": "{}"
    }
}
EOF
    )

    local result
    result=$(${DAEMON_NAME} tx wasm instantiate "${code_id}" "${init_msg}" \
        --label "treasury-fee-granter-devnet" \
        --admin "${DEPLOYER_ADDR}" \
        $(tx_flags) 2>&1)

    local txhash
    txhash=$(echo "${result}" | jq -r '.txhash // empty')
    if [ -z "${txhash}" ]; then
        log "WARN: Treasury instantiation may have failed: ${result}"
        TREASURY_ADDR=""
        return
    fi

    wait_for_tx "${txhash}"
    TREASURY_ADDR=$(${DAEMON_NAME} query tx "${txhash}" --node "${NODE}" --output json | \
        jq -r '.events[] | select(.type=="instantiate") | .attributes[] | select(.key=="_contract_address") | .value')
    log "Treasury/fee-granter contract: ${TREASURY_ADDR}"
}

fund_treasury() {
    if [ -z "${TREASURY_ADDR}" ]; then
        log "WARN: No treasury address, skipping funding"
        return
    fi

    local fund_amount="10000000000${DEFAULT_DENOM}"  # 10,000 XION
    log "Funding treasury with ${fund_amount}..."

    local result
    result=$(${DAEMON_NAME} tx bank send "${DEPLOYER_ADDR}" "${TREASURY_ADDR}" "${fund_amount}" \
        $(tx_flags) 2>&1)

    local txhash
    txhash=$(echo "${result}" | jq -r '.txhash // empty')
    if [ -n "${txhash}" ]; then
        wait_for_tx "${txhash}"
        log "Treasury funded"
    else
        log "WARN: Treasury funding may have failed: ${result}"
    fi
}

write_output() {
    log "Writing deployment output to ${OUTPUT_FILE}..."
    cat > "${OUTPUT_FILE}" <<EOF
# Generated by deploy-contracts.sh at $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Abstract Account contract (code_id=1)
AA_CONTRACT_ADDRESS=${AA_CONTRACT_ADDR:-}
# Treasury / Fee Granter contract (code_id=2)
FEE_GRANTER_ADDRESS=${TREASURY_ADDR:-}
# For dashboard .env
VITE_FEE_GRANTER_ADDRESS=${TREASURY_ADDR:-}
VITE_DEFAULT_ACCOUNT_CONTRACT_CODE_ID=1
EOF
    log "Output written. Contents:"
    cat "${OUTPUT_FILE}"
}

# ─── Main ─────────────────────────────────────────────────────────────────

main() {
    log "Starting post-genesis contract deployment..."
    wait_for_chain
    recover_key
    instantiate_abstract_account
    instantiate_treasury
    fund_treasury
    write_output
    log "Done!"
}

main "$@"
