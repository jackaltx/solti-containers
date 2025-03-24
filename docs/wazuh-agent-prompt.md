# Wazuh Agent Role Design Document

This document outlines the architecture, requirements, and implementation details for creating a complementary Wazuh agent role that works with the existing Wazuh server role.

## Role Structure

```
roles/
└── wazuh-agent/
    ├── defaults/
    │   └── main.yml          # Default variables
    ├── tasks/
    │   ├── main.yml          # Main tasks entry point
    │   ├── install.yml       # OS-specific installation tasks
    │   ├── configure.yml     # Configure agent
    │   ├── certificates.yml  # Certificate management
    │   └── register.yml      # Register with Wazuh manager
    ├── templates/
    │   └── ossec.conf.j2     # Agent configuration template
    ├── handlers/
    │   └── main.yml          # Service restart handlers
    └── vars/
        └── main.yml          # Internal variables
```

## Key Variables

```yaml
# Agent state
wazuh_agent_state: present     # Use 'absent' to remove

# Wazuh manager connection
wazuh_manager_host: "wazuh-server.example.com"
wazuh_manager_port: 1514
wazuh_registration_port: 1515

# Authentication method: 'password' or 'certificate'
wazuh_agent_auth_method: "certificate"

# Password-based registration
wazuh_enrollment_password: ""  # Should be passed from server

# Certificate-based authentication
wazuh_agent_cert_dir: "/var/ossec/etc/ssl"
wazuh_ca_cert_content: ""      # CA cert content from server
wazuh_agent_cert_content: ""   # Agent cert from server
wazuh_agent_key_content: ""    # Agent key from server

# Agent identification
wazuh_agent_name: "{{ inventory_hostname }}"
wazuh_agent_group: "default"

# Agent configuration
wazuh_agent_log_level: "info"
wazuh_agent_modules:
  - syscollector
  - sca
  - rootcheck
  - syscheck

# OS-specific packages
wazuh_repo_url:
  RedHat: "https://packages.wazuh.com/4.x/yum/"
  Debian: "https://packages.wazuh.com/4.x/apt/"

# Optional proxy settings
wazuh_agent_proxy_server: ""
wazuh_agent_proxy_port: 3128
wazuh_agent_proxy_user: ""
wazuh_agent_proxy_password: ""
```

## API Registration Workflow

For registering agents via the Wazuh API:

1. **Authentication**:
   - Obtain an API token from the Wazuh manager
   - Store token securely for subsequent operations

2. **Agent Registration**:
   - Register the agent with the manager via API
   - Retrieve the agent ID from the API response
   - Store agent ID for future operations

3. **Certificate Management** (if using certificate auth):
   - Generate agent certificate on the manager
   - Transfer certificates to the agent
   - Configure certificate paths in agent config

## CLI Registration Workflow

For registering agents via CLI commands:

1. **Agent ID Setup**:
   - Execute `manage_agents -a` to add agent on manager
   - Extract agent ID from command output

2. **Key Extraction**:
   - Get agent key using `manage_agents -e <agent_id>`
   - Transfer key to agent host

3. **Agent Import**:
   - Import key on agent using `manage_agents -i <key>`

## Certificate-Based Authentication Details

For certificate-based authentication:

1. **Certificate Requirements**:
   - CA certificate from Wazuh manager
   - Agent certificate with agent's ID in CN field
   - Agent private key

2. **File Locations**:
   - CA certificate: `/var/ossec/etc/rootca.pem`
   - Agent certificate: `/var/ossec/etc/client.cert`
   - Agent key: `/var/ossec/etc/client.key`

3. **Configuration Settings**:

   ```xml
   <client>
     <server>
       <address>{{ wazuh_manager_host }}</address>
       <port>{{ wazuh_manager_port }}</port>
       <protocol>tcp</protocol>
     </server>
     <crypto_method>aes</crypto_method>
     <key>/var/ossec/etc/client.key</key>
     <cert>/var/ossec/etc/client.cert</cert>
     <ca_store>/var/ossec/etc/rootca.pem</ca_store>
   </client>
   ```

## Integration Points with Server Role

The agent role will need certain information from the server role:

1. **Manager Information**:
   - Hostname/IP address
   - API port and credentials
   - Registration port

2. **Authentication Details**:
   - Enrollment password (for password-based auth)
   - CA certificate (for certificate-based auth)

3. **Agent Management**:
   - Group assignments
   - Policy configurations

## OS Support

The role should handle installation on various operating systems:

- RHEL/CentOS 7/8/9
- Debian 9/10/11/12
- Ubuntu 18.04/20.04/22.04
- Other platforms as needed

## Implementation Considerations

1. **Idempotency**:
   - Role should be rerunnable without errors
   - Should handle already registered agents

2. **Proxy Support**:
   - Include proxy configuration options
   - Support authenticated proxies

3. **Verification**:
   - Validate successful registration
   - Check agent-manager connection
   - Verify certificate validity

4. **Error Handling**:
   - Graceful failure with helpful messages
   - Retry logic for transient issues

5. **Security**:
   - Secure handling of credentials
   - Proper file permissions
   - Certificate validation

## Example Playbook Usage

```yaml
---
- name: Deploy Wazuh Agents
  hosts: agent_hosts
  vars:
    wazuh_manager_host: "wazuh.example.com"
    wazuh_agent_auth_method: "certificate"
    wazuh_ca_cert_content: "{{ lookup('file', '/path/to/rootca.pem') }}"
  roles:
    - role: wazuh-agent
```

This document provides a foundation for implementing a comprehensive Wazuh agent role that integrates with the existing server role, focusing on certificate-based authentication for enhanced security.
