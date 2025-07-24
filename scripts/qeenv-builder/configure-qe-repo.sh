#!/bin/bash

set -eux

function create_images_repo_vm() {
    # Check if VM already exists
    if ! virsh list --all | grep -q "${VM_NAME}"; then
        echo "VM ${VM_NAME} does not exist, creating it"
        virt-install \
            --name ${VM_NAME} \
            --vcpus 2 \
            --memory 4096 \
            --disk path=${HOME}/${VM_NAME}.qcow2,size=120 \
            --network network=isolated,model=virtio \
            --network network=vm-bridge0,model=virtio \
            --events on_reboot=restart \
            --location "${HOME}/ISO/${ISO}" \
            --initrd-inject="${HOME}/ISO/kickstart-repo-vm.ks" \
            --extra-args 'inst.ks=file:kickstart-repo-vm.ks' \
            --wait 10
    else
        echo "VM ${VM_NAME} already exists, skipping creation"
    fi

    # Loop until we successfully get the VM's IP and configure it
    while true; do
        MAC=$(virsh domiflist ${VM_NAME} | grep bridge | awk '{print $NF}')
        IP=$(nmap -sn 10.1.235.0/24 > /dev/null && arp -n | grep ${MAC} | awk '{print $1}')
        
        if [ -n "${IP}" ] && ssh -o ConnectTimeout=10 -o BatchMode=yes -l redhat ${IP} "sudo hostnamectl set-hostname --static ${VM_NAME}.local" 2>/dev/null; then
            echo "IP: ${IP}"
            virsh desc ${VM_NAME} --live --config --title --new-desc agullon - ${IP}
            break
        fi
        
        echo "Waiting for VM to be ready..."
        sleep 10
    done
}

function configure_images_repo_vm() {
    sudo subscription-manager register --force --org=11009103 --activationkey=microshift-test
    sudo dnf upgrade-minimal --assumeyes --quiet --releasever 9.6

    [ -d microshift ] || git clone --depth 1 https://github.com/openshift/microshift.git

    # # to install nginx package
    sudo bash microshift/scripts/devenv-builder/configure-composer.sh

    # Make sure libvirtd is running. We do this here, because some of the other scripts use virsh.
    bash -x microshift/scripts/devenv-builder/manage-vm.sh config

    # Clean up the image builder cache to free disk for virtual machines
    bash -x microshift/scripts/devenv-builder/cleanup-composer.sh -full
}

function copy_secrets() {
    scp -r /home/microshift/.aws/ microshift@${IP}:/home/microshift/.aws/
    ssh microshift@${IP} "set -eux; $(typeset -f); get_cache_from_s3"

    ssh microshift@${IP} rm -rf /home/microshift/.pull-secret.json
    scp /home/microshift/.pull-secret-microshift-dev.json microshift@${IP}:/home/microshift/.pull-secret.json
}

function get_cache_from_s3() {
    SCENARIO_BUILD_BRANCH="main"
    # SCENARIO_BUILD_TAG="$(date '+%y%m%d')"
    SCENARIO_BUILD_TAG="250722"

    export AWS_BUCKET_NAME="microshift-build-cache-us-west-2"

    sudo chown -R microshift:microshift /home/microshift/microshift/_output
    if bash -x microshift/test/bin/manage_build_cache.sh verify -b "${SCENARIO_BUILD_BRANCH}" -t "${SCENARIO_BUILD_TAG}" ; then
        
        sudo mkdir -p /home/microshift/microshift/_output/test-images/vm-storage/
        sudo chown -R microshift:microshift /home/microshift/microshift/_output/test-images

        bash -x microshift/test/bin/manage_build_cache.sh download -b "${SCENARIO_BUILD_BRANCH}" -t "${SCENARIO_BUILD_TAG}"
    fi
}

function create_rpm_repos() {
    ls -d /home/microshift/microshift/_output/test-images/brew-rpms/4*/*/ | while read -r dir; do
        createrepo "${dir}"
    done
}

function get_container_images() {
    export CONTAINER_LIST="/home/microshift/microshift/_output/test-images/container-images-list"

    rm -f "${CONTAINER_LIST}"

    find /home/microshift/microshift/_output/test-images/brew-rpms/ -name "microshift-release-info*" | while read -r rpm; do
        rpm2cpio "$rpm" | cpio  -i --to-stdout "*release-$(uname -m).json" 2> /dev/null | jq -r '[ .images[] ] | join(",")' | sed 's/,/\n/g' >> "${CONTAINER_LIST}"
    done
}

function start_mirror_registry() {
    sudo mkdir -p /home/microshift/microshift/_output/test-images/
    sudo chown -R microshift:microshift /home/microshift/microshift/_output/test-images
    
    # Set up the hypervisor configuration for the tests and start webserver
    bash -x microshift/test/bin/manage_hypervisor_config.sh create

    # Delete running containers if any
    for n in postgres redis quay ; do
        local cn="microshift-${n}"
        echo "Removing '${cn}' container"
        sudo podman rm -f --time 0 "${cn}" || true
    done

    # Setup a container registry and mirror images.
    bash -x microshift/test/bin/mirror_registry.sh
}


VM_NAME="${1:-microshift-vm-repo-images}"
ISO="${2:-rhel-9.6-x86_64-dvd.iso}"

if [ -z "${VM_NAME}" ]; then echo "VM_NAME is not set" && exit 1; fi
if [ -z "${ISO}" ]; then echo "ISO is not set" && exit 1; fi


create_images_repo_vm

ssh microshift@${IP} "set -eux; $(typeset -f); configure_images_repo_vm"

copy_secrets

ssh microshift@${IP} "set -eux; $(typeset -f); create_rpm_repos"

ssh microshift@${IP} "set -eux; $(typeset -f); get_container_images"

ssh microshift@${IP} "set -eux; $(typeset -f); start_mirror_registry"
