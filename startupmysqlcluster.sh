#!/bin/bash

set -e
set -o pipefail

MASTER_NODE_IP="192.168.1.130"
WORKER_NODE1_IP="192.168.1.131"
# WORKER_NODE2_IP="192.168.1.132"

LAB_DIR="/home/pumej/Projects/MySql_cluster_project"
INVENTORY_FILE="$LAB_DIR/inventory.ini"
PLAYBOOK_FILE="$LAB_DIR/deploy_mysql_cluster.yml"

echo
echo "======================================================================"
echo "              MYSQL INNODB CLUSTER DEPLOYMENT"
echo "======================================================================"
echo

# ----------------------------------------------------------------------
# Start VMs
# ----------------------------------------------------------------------

echo "➡️  Starting up VMs..."

cd "$LAB_DIR"

vagrant.exe up

echo "✅ VMs are running."

# ----------------------------------------------------------------------
# Verify required files
# ----------------------------------------------------------------------

echo "🔎 Checking deployment files..."

if [ ! -f "$INVENTORY_FILE" ]; then
    echo "❌ Ansible inventory not found:"
    echo "   $INVENTORY_FILE"
    exit 1
fi

if [ ! -f "$PLAYBOOK_FILE" ]; then
    echo "❌ Ansible playbook not found:"
    echo "   $PLAYBOOK_FILE"
    exit 1
fi

echo "✅ Inventory found: $INVENTORY_FILE"
echo "✅ Playbook found:  $PLAYBOOK_FILE"

# ----------------------------------------------------------------------
# Remove old SSH fingerprints
# ----------------------------------------------------------------------

echo "🔑 Removing old SSH fingerprints..."

ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$MASTER_NODE_IP" 2>/dev/null || true
ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$WORKER_NODE1_IP" 2>/dev/null || true
# ssh-keygen -f "$HOME/.ssh/known_hosts" -R "$WORKER_NODE2_IP" 2>/dev/null || true

echo -e "\n🔐 Fixing private key permissions..."
chmod 600 $LAB_DIR/.vagrant/machines/*/virtualbox/private_key

# ----------------------------------------------------------------------
# Wait for SSH
# ----------------------------------------------------------------------

wait_for_ssh() {

    local ip="$1"

    echo "⏳ Waiting for SSH on $ip..."

    for _ in {1..30}; do

        if nc -z "$ip" 22 2>/dev/null; then
            echo "✅ SSH is available on $ip"
            return 0
        fi

        sleep 3

    done

    echo "❌ Timed out waiting for SSH on $ip"

    return 1
}

wait_for_ssh "$MASTER_NODE_IP"
wait_for_ssh "$WORKER_NODE1_IP"
# wait_for_ssh "$WORKER_NODE2_IP"

# ----------------------------------------------------------------------
# Check Ansible
# ----------------------------------------------------------------------

echo "🔎 Checking Ansible..."

if ! command -v ansible >/dev/null 2>&1; then

    echo "❌ Ansible is not installed in WSL."

    echo "Install it with:"
    echo "    sudo apt update"
    echo "    sudo apt install ansible -y"

    exit 1
fi

echo "✅ Ansible found:"
ansible --version | head -n 1

# ----------------------------------------------------------------------
# Test Ansible connectivity
# ----------------------------------------------------------------------

echo
echo "📡 Testing Ansible connectivity..."

if ! ANSIBLE_HOST_KEY_CHECKING=False \
    ansible \
    -i "$INVENTORY_FILE" \
    all \
    -m ping; then

    echo
    echo "❌ Ansible cannot connect to one or more nodes."
    echo "Check:"
    echo "  - VM networking"
    echo "  - SSH"
    echo "  - Vagrant key"
    echo "  - inventory.ini"

    exit 1
fi

echo "✅ All nodes responded successfully."

# ----------------------------------------------------------------------
# Run Ansible playbook
# ----------------------------------------------------------------------

echo "🚀 Starting Oracle MySQL 8.4 deployment..."

if ! ANSIBLE_HOST_KEY_CHECKING=False \
    ansible-playbook \
    -i "$INVENTORY_FILE" \
    "$PLAYBOOK_FILE" \
    --ask-vault-pass \
    -vv; then
    echo "❌ Ansible deployment failed."
    exit 1
fi

# ----------------------------------------------------------------------
# Complete
# ----------------------------------------------------------------------

echo "======================================================================"
echo "              MYSQL INNODB CLUSTER DEPLOYMENT COMPLETE"
echo "======================================================================"
echo "✅ Master:   $MASTER_NODE_IP"
echo "✅ Worker 1: $WORKER_NODE1_IP"
# echo "✅ Worker 2: $WORKER_NODE2_IP"
echo "======================================================================"