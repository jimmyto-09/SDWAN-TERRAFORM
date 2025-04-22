#!/bin/bash

CPE_IP=$(kubectl get pod vnf-cpe -n rdsv -o jsonpath='{.status.podIP}')

echo "{\"cpe_ip\": \"$CPE_IP\"}"
