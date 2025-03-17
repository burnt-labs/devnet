#!/usr/bin/env bash
set -euxo pipefail

apt-get install -y --no-install-recommends jq

function create_signing_key() {
    awslocal --endpoint-url=http://localhost:4566 kms create-key \
      --description "Signing Key" \
      --key-usage "SIGN_VERIFY" \
      --origin "AWS_KMS" \
      --customer-master-key-spec "RSA_4096" \
      --key-spec "RSA_4096"

    keyId=$(awslocal --endpoint-url=http://localhost:4566 kms list-keys | jq -r '.Keys[0].KeyId')

    awslocal --endpoint-url=http://localhost:4566 kms create-alias \
      --alias-name "alias/signing-key" \
      --target-key-id $keyId

    awslocal --endpoint-url=http://localhost:4566 kms list-aliases

    awslocal kms get-public-key --key-id $keyId
}

create_signing_key