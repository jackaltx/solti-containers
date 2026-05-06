# Changelog

All notable changes to this collection will be documented here.

## [1.0.0] - 2026-05-05

### Added
- Initial collection release
- 14 service roles: `_base`, `traefik`, `hashivault`, `redis`, `elasticsearch`, `minio`, `mongodb`, `influxdb3`, `mattermost`, `grafana`, `gitea`, `obsidian`, `conduit`, `dns_service`
- Podman rootless containers with Quadlet/systemd integration
- Shared `_base` role pattern for common container setup (networks, directories, SELinux)
- Dynamic playbook generation via `manage-svc.sh`
- Molecule testing with Podman scenarios for Debian 12, Rocky 9, and Ubuntu 24
- Support for RHEL 9+, CentOS Stream 9+, Debian 12+, Ubuntu 22.04+
