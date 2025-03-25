# Remove any existing containers
podman rm -f wazuh-indexer 2>/dev/null || true

# Create data directory with permissions
mkdir -p ~/wazuh-data/data/indexer
chown -R $(id -u):$(id -g) ~/wazuh-data/data/indexer
chmod 777 ~/wazuh-data/data/indexer

# Run container with security options
podman run -d --name wazuh-indexer \
  -e "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m -Djava.security.manager=allow" \
  -e "bootstrap.memory_lock=true" \
  -e "discovery.type=single-node" \
  -v ~/wazuh-data/config/indexer:/usr/share/wazuh-indexer/config:Z \
  -v ~/wazuh-data/data/indexer:/var/lib/wazuh-indexer:Z \
  -v ~/wazuh-data/certs:/etc/ssl/wazuh:Z \
  --security-opt seccomp=unconfined \
  --security-opt label=disable \
  --ulimit nofile=65535:65535 \
  --ulimit memlock=-1:-1 \
  docker.io/wazuh/wazuh-indexer:4.7.2
