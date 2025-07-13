#!/bin/bash
# Test script for Wazuh Indexer with proper user mapping

# Remove any existing containers
podman rm -f wazuh-indexer 2>/dev/null || true

# Ensure data directory exists with proper permissions
mkdir -p ~/wazuh-data/data/indexer
mkdir -p ~/wazuh-data/config/indexer
mkdir -p ~/wazuh-data/certs

# Set permissions to 777 for testing
chmod 777 ~/wazuh-data/data/indexer

# Run the container with explicitly mapped user ID and disabled security
podman run -d --name wazuh-indexer \
  --user 1000:1000 \
  --security-opt label=disable \
  -e "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m -Djava.security.manager=allow" \
  -e "bootstrap.memory_lock=true" \
  -e "discovery.type=single-node" \
  -v ~/wazuh-data/config/indexer:/usr/share/wazuh-indexer/config:Z \
  -v ~/wazuh-data/data/indexer:/var/lib/wazuh-indexer:Z \
  -v ~/wazuh-data/certs:/etc/ssl/wazuh:Z \
  --ulimit nofile=65535:65535 \
  --ulimit memlock=-1:-1 \
  docker.io/wazuh/wazuh-indexer:4.7.2

# Check if it's running
echo "Waiting for container to start..."
sleep 5
podman ps -a | grep wazuh-indexer

# Check logs
echo "Container logs:"
podman logs wazuh-indexer
