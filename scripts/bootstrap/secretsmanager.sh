#!/bin/bash

#
awslocal secretsmanager create-secret \
    --name all-secrets \
    --description "LocalStack Secrets" \
    --secret-string '{"username": "SOMBODY","password": "THATIUSEDTOKNOW"}'

# TODO - try --secret-string file://secrets.json \