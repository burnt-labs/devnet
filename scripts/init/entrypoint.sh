#!/usr/bin/env bash
set -euo pipefail


# This script is used to initialize the chain
export HOME=$(pwd)
SCRIPTS_DIR=$(dirname "$0")
VALIDATOR_ID=0

IMPORT_MODULES=(
  "abstractaccount"
  "auth"
  "bank"
  "bank_denoms_metadata"
  "consensus" 
  "distribution"
  "globalfee"
  "gov"
  "jwk"
  "mint"
  "slashing" 
  "staking" 
  "tokenfactory"
  "wasm"
)

# Load environment variables
if [ -f "${HOME}/.env" ]; then
    source "${HOME}/.env"
fi

# Temporary directory for intermediate files
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

# cosmos_sdk_version > v0.47 genesis commands are moved under app genesis cmd
GENESIS="genesis"
ADD_INIT_FLAGS="--default-denom=${DEFAULT_DENOM}"

sleep_random() {
    local random_number=$((RANDOM % 3000))
    local sleep_time
    sleep_time=$(bc <<< "scale=3; $random_number / 1000")
    sleep "$sleep_time"
}

select_num() {
    while : ; do
        if [[ ${VALIDATOR_ID} -eq 0 ]]; then
            sleep_random
        elif [[ ${VALIDATOR_ID} -ge ${NUM_VALIDATORS} ]]; then
            VALIDATOR_ID=0
        fi
        if [[ ! -f "${HOME}/.shared/claims/validator-${VALIDATOR_ID}" ]]; then
            touch "${HOME}/.shared/claims/validator-${VALIDATOR_ID}"
            echo "VALIDATOR_ID=${VALIDATOR_ID}" > "${HOME}/.env"
            break
        fi
        VALIDATOR_ID=$((VALIDATOR_ID + 1))
    done
}

# Initialize the chain, this creates the genesis.json, config.toml and app.toml files
initialize_chain() {
    local validator="$1"
    # Initialize the chain
    echo "Initializing chain ${CHAIN_ID}..."
    "${DAEMON_NAME}" init "${validator}" --default-denom="${DEFAULT_DENOM}" --chain-id="${CHAIN_ID}" \
    ${ADD_INIT_FLAGS} > /dev/null 2>&1
}

# Initialize a single account
initialize_account() {
    local name="$1"
    local account="$2"
    local index="$3"
    local amount="${4}"
    echo "Initializing account ${name}..."
    echo "${MNEMONIC}" | "${DAEMON_NAME}" keys add "${name}" --account "${account}" --index "${index}" --keyring-backend test --recover --output json >> "${HOME}/keys.json"
    "${DAEMON_NAME}" "${GENESIS}" add-genesis-account "${name}" "${amount}${DEFAULT_DENOM}" --keyring-backend test --append
}

# Initialize all accounts
initialize_all_accounts() {
    # AA Api
    initialize_account "abstraxion" 1 0 $(( GENESIS_AMOUNT ))

    # Faucet
    initialize_account "faucet" 0 0 $(( GENESIS_AMOUNT ))
    for num in $(seq 1 ${FAUCET_ACCOUNTS}); do
        initialize_account "faucet-${num}" 0 "${num}" "$(( FAUCET_AMOUNT ))"
    done

    # Validators
    for num in $(seq 1 $((NUM_VALIDATORS - 1))); do
        local validator="${DAEMON_NAME}-${num}"
        initialize_account "${validator}" 2 "${num}" "$(( GENTX_AMOUNT + 1000000 ))"
    done
}

initialize_validator() {
    local num="$1"
    local validator="${DAEMON_NAME}-${num}"
    initialize_chain "${validator}"
    initialize_account "${validator}" 2 "${num}" "$(( GENTX_AMOUNT + 1000000 ))"
    create_gentx "${validator}"
    modify_config_toml "${validator}"
}

modify_config_toml() {
    local validator="$1"
    echo "Modifying config.toml for ${validator}..."
    # Modify the config.toml file
    sed -i "s/^addr_book_strict =.*$/addr_book_strict = false/" "${DAEMON_HOME}/config/config.toml"
    sed -i "s/^timeout_commit =.*$/timeout_commit = \"1s\"/" "${DAEMON_HOME}/config/config.toml"
}

create_gentx() {
    local validator="$1"
    echo "Creating Gentx for ${validator}..."
    # Create a gentx for the validator and add it to the genesis file
    "${DAEMON_NAME}" "${GENESIS}" gentx "${validator}" "${GENTX_AMOUNT}${DEFAULT_DENOM}" \
        --keyring-backend test \
        --chain-id="${CHAIN_ID}"
    mkdir -p "${HOME}/.shared/gentxs"
    cp -a ${DAEMON_HOME}/config/gentx/* "${HOME}/.shared/gentxs/${validator}.gentx.json"
}

import_modules() {
    for module in "${IMPORT_MODULES[@]}"; do
        import_module_params "${module}"
    done
}

import_module_params() {
    local module="$1"
    local params jq_script query="params"

    case "$module" in
        "abstractaccount")
            jq_script='.app_state["abstractaccount"]["params"] += $params'
            module="abstract-account"
            ;;
        "bank_denoms_metadata")
            module="bank"
            query="denoms-metadata"
            jq_script='.app_state[$module]["denom_metadata"] = [$params["metadatas"][] | select(.name == env.DENOM_METADATA_NAME)]'
            ;;
        "consensus")
            jq_script='.consensus["params"]["block"] = $params["params"]["block"]' 
            ;;
        "globalfee")
            jq_script='.app_state[$module]["params"]["minimum_gas_prices"] = $params["minimum_gas_prices"]'
            ;;
        *)
            jq_script='.app_state[$module]["params"] = (.app_state[$module]["params"] + $params["params"])'
            ;;
    esac

    echo "Querying $module $query..."
    params="$("${DAEMON_NAME}" query "$module" "$query" --node "${SOURCE_CHAIN_RPC}" --output json || echo "{}")"

    echo "Modifying $module $query..."
    modify_genesis_jq "$module" "$jq_script" "$params"
}

import_contracts() {
    local code_id=0
    for source_code_id in ${SOURCE_CHAIN_CODE_IDS}; do
        code_id=$((code_id + 1))
        ${DAEMON_NAME} query wasm code "${source_code_id}" ${TMP_DIR}/code-bytes.wasm --node "${SOURCE_CHAIN_RPC}" --output raw
        local code_hash=$(sha256sum ${TMP_DIR}/code-bytes.wasm | head -c 64 | xxd -r -p | base64)
        base64 -i ${TMP_DIR}/code-bytes.wasm | jq -Rs \
            --arg code_id $code_id \
            --arg code_hash $code_hash \
            --arg pinned false \
            --arg creator ${ABSTRAXION_ADDRESS} \
            '{"code_bytes": ., "code_id": $code_id, "creator": $creator, "code_hash": $code_hash, "pinned": $pinned}' \
            > "${TMP_DIR}/code-bytes.json"
        jq -f ${SCRIPTS_DIR}/accounts.jq \
            --arg execute add_code_id \
            --slurpfile vars "${TMP_DIR}/code-bytes.json" \
            "${DAEMON_HOME}/config/genesis.json" > "${TMP_DIR}/genesis.json" 
        mv "${TMP_DIR}/genesis.json" "${DAEMON_HOME}/config/genesis.json"
    done
    jq -f ${SCRIPTS_DIR}/accounts.jq \
        --arg execute add_sequences \
        --argjson vars "{\"lastCodeId\": $((code_id + 1)), \"lastContractId\": ${code_id}}" \
        "${DAEMON_HOME}/config/genesis.json" > "${TMP_DIR}/genesis.json" 
        mv "${TMP_DIR}/genesis.json" "${DAEMON_HOME}/config/genesis.json"
}

modify_genesis_jq() {
    local module="$1"
    local jq_script="$2"
    local params="$3"
    jq --arg module "$module" --argjson params "$params" \
        "$jq_script" "${DAEMON_HOME}/config/genesis.json" > "${TMP_DIR}/genesis.json"
    diff -u "${DAEMON_HOME}/config/genesis.json" "${TMP_DIR}/genesis.json" || true 
    mv "${TMP_DIR}/genesis.json" "${DAEMON_HOME}/config/genesis.json"
}

initialize_genesis() {
    # Wait for all gentxs to be created
    for num in $(seq 0 $((NUM_VALIDATORS - 1))); do
        local validator="${DAEMON_NAME}-${num}"
        until [[ -f ${HOME}/.shared/gentxs/${validator}.gentx.json ]]; do
            echo "Waiting for ${validator}.gentx.json to be created..."
            sleep 1
        done
    done
    initialize_all_accounts

    if [[ -n "${SOURCE_CHAIN_ID}" ]]; then
        echo "Importing module settings from ${SOURCE_CHAIN_ID}..."
        import_modules
    fi

    if [[ -n "${SOURCE_CHAIN_CODE_IDS}" ]]; then
        echo "Importing contracts ${SOURCE_CHAIN_CODE_IDS} from ${SOURCE_CHAIN_ID}..."
        import_contracts
    fi

    if [[ -n "${MODIFY_GENESIS_JQ}" ]]; then
        echo "Modifying genesis.json..."
        modify_genesis_jq "" "${MODIFY_GENESIS_JQ}" "{}"
    fi

    echo "Collecting gentxs..."
    "${DAEMON_NAME}" "${GENESIS}" collect-gentxs \
    --gentx-dir="${HOME}/.shared/gentxs" \
    > /dev/null 2>&1

    # Modify the genesis.json
    sed -e "s/stake/${DEFAULT_DENOM}/g" \
        -i "${DAEMON_HOME}/config/genesis.json"

    # Copy final genesis
    cp -a "${DAEMON_HOME}/config/genesis.json" "${HOME}/.shared/genesis.json"
}

validate_genesis_file() {
    echo "Validating new genesis file..."
    "${DAEMON_NAME}" "${GENESIS}" validate-genesis "${HOME}/.shared/genesis.json" --trace
}

wait_for_genesis() {
    # Wait for genesis.json to be created
    until [[ -f ${HOME}/.shared/genesis.json ]]; do
        echo "Waiting for genesis.json to be created..."
        sleep 1
    done
    validate_genesis_file
    cp -a "${HOME}/.shared/genesis.json" "${DAEMON_HOME}/config/genesis.json"
}

is_sourced() {
    # https://unix.stackexchange.com/a/215279
    [[ "${#FUNCNAME[@]}" -ge 2 ]] \
        && [[ "${FUNCNAME[0]}" = '_is_sourced' ]] \
        && [[ "${FUNCNAME[1]}" = 'source' ]]
}

init() {
    # genesis.json in shared
    if [[ -f ${HOME}/.shared/genesis.json ]]; then
        cp -a "${HOME}/.shared/genesis.json" "${DAEMON_HOME}/config/genesis.json"
    fi

    if [[ ! -f ${DAEMON_HOME}/config/genesis.json ]]; then
        mkdir -p "${HOME}/.shared/claims"
        select_num
        initialize_validator "${VALIDATOR_ID}"
        if [[ ${VALIDATOR_ID} -eq 0 ]]; then
            initialize_genesis
        else
            wait_for_genesis
        fi
    fi
}

init_cosmovisor() {
    export DAEMON_NAME
    export DAEMON_HOME
    export DAEMON_ALLOW_DOWNLOAD_BINARIES=true
    export DAEMON_DOWNLOAD_MUST_HAVE_CHECKSUM=true
    export UNSAFE_SKIP_BACKUP=true
    cosmovisor init $(which ${DAEMON_NAME})
}

if ! is_sourced; then
    if grep -q cosmovisor <<<$1; then
        init_cosmovisor
    fi
	init && exec "$@"
fi
