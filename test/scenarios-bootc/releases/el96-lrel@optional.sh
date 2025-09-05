#!/bin/bash

# Sourced from scenario.sh and uses functions defined there.

# Redefine network-related settings to use the dedicated network bridge
VM_BRIDGE_IP="$(get_vm_bridge_ip "${VM_MULTUS_NETWORK}")"
# shellcheck disable=SC2034  # used elsewhere
WEB_SERVER_URL="http://${VM_BRIDGE_IP}:${WEB_SERVER_PORT}"

scenario_create_vms() {
    prepare_kickstart host1 kickstart-bootc.ks.template "rhel96-bootc-brew-${LATEST_RELEASE_TYPE}-with-optional"
    # Two nics - one for macvlan, another for ipvlan (they cannot enslave the same interface)
    launch_vm --boot_blueprint rhel96-bootc --network "${VM_MULTUS_NETWORK},${VM_MULTUS_NETWORK}"
}

scenario_remove_vms() {
    remove_vm host1
}

scenario_run_tests() {
        run_tests host1 \
        --variable "PROMETHEUS_HOST:$(hostname)" \
        --variable "PROMETHEUS_PORT:9092" \
        --variable "LOKI_HOST:$(hostname)" \
        --variable "LOKI_PORT:3200" \
        --variable "PROM_EXPORTER_PORT:8889" \
        suites/optional/
}
