# Document Hashivault role

## Introduction

Claude write an introcution to hashivault.

## Deployment Scenario

on local machine, listening to port xxx  

## Install

### Prepare

```
manage-svc.sh hashivault prepare
```

Runs once
creates configuration and data directories

### Deploy

```
manage-svc.sh hashivault deploy
```

Idempotent
runs rootless

```
$ ls -1 ~/.config/containers/systemd/vault*
/home/lavender/.config/containers/systemd/vault.pod
/home/lavender/.config/containers/systemd/vault-svc.container
```

To get status info

```
$ systemctl --user status vault-svc
● vault-svc.service - HashiCorp Vault Container
     Loaded: loaded (/home/lavender/.config/containers/systemd/vault-svc.container; generated)
    Drop-In: /usr/lib/systemd/user/service.d
             └─10-timeout-abort.conf
     Active: active (running) since Mon 2025-03-03 15:29:24 CST; 1h 32min ago
 Invocation: 93fc66d5087c43e3abc57921aab5d52f
   Main PID: 3337 (conmon)
      Tasks: 14 (limit: 74224)
     Memory: 378.4M (peak: 379.6M)
        CPU: 2.965s
     CGroup: /user.slice/user-1000.slice/user@1000.service/app.slice/vault-svc.service
             ├─libpod-payload-b3fcc94cd6a1c263626ac6283d30ab854d9437379ec1a618b233c7c929891819
             │ ├─3346 /usr/bin/dumb-init /bin/sh /usr/local/bin/docker-entrypoint.sh server
             │ └─3359 vault server -config=/vault/config -dev-root-token-id= -dev-listen-address=0.0.0.0:8200
             └─runtime
               └─3337 /usr/bin/conmon --api-version 1 -c b3fcc94cd6a1c263626ac6283d30ab854d9437379ec1a618b233c7c929891819 -u b3fcc94cd6a1c263626ac6283d30ab854d9437379ec1a618b233c7c929891819 -r /usr/bin/c>

Mar 03 15:29:24 firefly vault-svc[3337]:                  Storage: file
Mar 03 15:29:24 firefly vault-svc[3337]:                  Version: Vault v1.15.6, built 2024-02-28T17:07:34Z
```

## Configure

generates tokens and does the unseal

```
./svc-exec.sh hashivault initialize
```

install k-v, pki, ssh, transit?

```
./svc-exec.sh hashivault configure
```

import service env file to prepopulate the the kv
this is for my poject...put these in your inventory, host_vars or group_vars.

```
./svc-exec.sh hashivault vault-secrets
```

## Restart

vault must be unsealed on restart.

```
./svc-exec.sh hashivault unseal

```
