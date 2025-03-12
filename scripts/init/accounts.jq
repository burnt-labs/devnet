#!/usr/bin/env jq

def add_code_id: 
    .app_state.wasm.codes += [{
        "code_id": $code_id,
        "code_bytes": $code_bytes,
        "creator": $creator_address,
        "instantiate_permission": {
            "permission": "Everybody",
            "address": "",
            "addresses": []
        }
    }];

def add_genesis_account: 
    .app_state["auth"]["accounts"] += [{
        "@type": "/cosmos.auth.v1beta1.BaseAccount", 
        "address": $vars.addr, 
        "pub_key": null, 
        "account_number": ($vars.account_number | tostring), 
        "sequence": "0"
    }];

def add_genesis_balance: 
    .app_state["bank"]["balances"] += [{
        "address": $vars.addr, 
        "coins": $vars.coins
    }];

def main:
    if $execute == "add_code_id" then add_code_id
    if $execute == "add_genesis_account" then add_genesis_account
    if $execute == "add_genesis_balance" then add_genesis_balance
    else error("Unknown function: " + $execute)
    end;

main
