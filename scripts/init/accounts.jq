def add_code_id: 
    .app_state.wasm.codes += [{
        "code_id": ($vars[0].code_id | tostring),
        "code_bytes": $vars[0].code_bytes,
        "code_info": {
            "code_hash": $vars[0].code_hash,
            "creator": $vars[0].creator,
            "instantiate_config": {
                "permission": "Everybody",
                "addresses": []
            }
        },
        "pinned": false
    }];

def add_sequences: 
    .app_state.wasm.sequences += [
      {
        "id_key": "BGxhc3RDb2RlSWQ=",
        "value": $vars.lastCodeId
      },
      {
        "id_key": "BGxhc3RDb250cmFjdElk",
        "value": $vars.lastContractId
      }
    ];

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
    elif $execute == "add_sequences" then add_sequences
    elif $execute == "add_genesis_account" then add_genesis_account
    elif $execute == "add_genesis_balance" then add_genesis_balance
    else error("Unknown function: " + $execute)
    end;

main
