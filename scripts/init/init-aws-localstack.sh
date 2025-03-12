#!/bin/bash

# Create an SQS queue
awslocal sqs create-queue --queue-name q1

#
awslocal secretsmanager create-secret \
    --name all-secrets \
    --description "LocalStack Secrets" \
    --secret-string /secrets.json