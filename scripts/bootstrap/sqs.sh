#!/usr/bin/env bash
set -euxo pipefail

create_queue() {
    local Q="${1}"
    awslocal --endpoint-url=http://localhost:4566 sqs \
      create-queue \
      --queue-name ${Q} \
      --region ${AWS_DEFAULT_REGION}
}

create_fifo_queue() {
    local Q="${1}.fifo"
    awslocal --endpoint-url=http://localhost:4566 sqs \
      create-queue \
      --queue-name ${Q} \
      --region ${AWS_DEFAULT_REGION} \
      --attributes "FifoQueue=true"
}

create_queue "testq"
create_fifo_queue "testq"