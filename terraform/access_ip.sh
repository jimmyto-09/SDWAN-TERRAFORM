#!/bin/bash

ACCESS_IP=$(kubectl get pod vnf-access -n rdsv -o jsonpath='{.status.podIP}')

echo "{\"access_ip\": \"$ACCESS_IP\"}"
