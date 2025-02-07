# Mattermost Podman Role

This role manages the installation and configuration of Mattermost using rootless Podman containers.

## Requirements

- Podman
- Systemd
- User with sudo access

## Role Variables

See defaults/main.yml for all available variables and their default values.

## Example Playbook

```yaml
- hosts: servers
  roles:
    - role: mattermost
      vars:
        mattermost_postgres_password: "secure_password"
        mattermost_port: 8065
```

## License

MIT

## Author Information

Created by Anthropic. Extended by the community.