#!/bin/bash

# Create an SQS queue
awslocal sqs create-queue --queue-name q1

#
awslocal secretsmanager create-secret \
    --name all-secrets \
    --description "LocalStack Secrets" \
    --secret-string '{"username": "admin", "password": "password"}'

#
awslocal kms create-key \
  --tags '[{"TagKey":"_custom_id_","TagValue":"00000000-0000-0000-0000-000000000001"}]'