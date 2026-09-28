#!/usr/bin/env bash
# Run only in a disposable Debian container with samba, smbclient, python3 and sudo.
set -euo pipefail
[[ -e /.dockerenv && $EUID -eq 0 ]] || { echo 'Run this check in a disposable container.' >&2; exit 1; }
useradd --create-home spoke
groupadd ggc_group
useradd --system --gid ggc_group ggc_user
printf 'spoke ALL=(ALL) NOPASSWD: ALL\n' >/etc/sudoers.d/spoke-test
chmod 440 /etc/sudoers.d/spoke-test
# Containers have no systemd/NetworkManager; record these commands without changing networking.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>/tmp/systemctl-calls\n' >/usr/local/bin/systemctl
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>/tmp/nmcli-calls\n' >/usr/local/bin/nmcli
chmod +x /usr/local/bin/systemctl /usr/local/bin/nmcli
runuser -u spoke -- bash <<'BASH'
set -euo pipefail
source /src/install.sh
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
FBI_SAMBA_USER=FBI FBI_SAMBA_PASSWORD=test-only-password FBI_GROUP=venue-fbi
MAX_FBI_WATCH_DIR='/srv/samba/custom FBI'
MAX_FBI_LOCAL_DB_PATH=/var/lib/spoke-onsite/max-fbi-agent.sqlite
FBI_ROUTE_NETWORK=10.128.211.0 FBI_ROUTE_MASK=255.255.255.0 FBI_ROUTE_GATEWAY=192.168.70.225
FBI_ROUTE_CIDR=$(route_cidr)
FBI_ROUTE_CONNECTION=12345678-1234-1234-1234-123456789abc FBI_ROUTE_DEVICE=eth0
setup_fbi_samba
[[ -z ${FBI_SAMBA_PASSWORD+x} ]]
# Reapply the config to verify existing accounts and the managed block are reusable.
FBI_SAMBA_PASSWORD=test-only-password
setup_fbi_samba
BASH
testparm -s /etc/samba/smb.conf >/dev/null
[[ $(grep -c '^# BEGIN SPOKE FBI$' /etc/samba/smb.conf) == 1 ]]
for user in spoke ggc_user FBI; do
  id -nG "$user" | tr ' ' '\n' | grep -Fx venue-fbi >/dev/null
done
[[ $(getent passwd FBI | cut -d: -f7) == /usr/sbin/nologin ]]
grep -Fx 'connection modify uuid 12345678-1234-1234-1234-123456789abc +ipv4.routes 10.128.211.0/24 192.168.70.225' /tmp/nmcli-calls
grep -Fx 'device reapply eth0' /tmp/nmcli-calls
smbd -D
umask 077
printf 'username = FBI\npassword = test-only-password\n' >/tmp/smb-auth
printf 'test FBI export\n' >/tmp/export.csv
smbclient //127.0.0.1/fbi -A /tmp/smb-auth -m NT1 --option='client min protocol=NT1' \
  -c 'put /tmp/export.csv FBI.csv; put /tmp/export.csv FBI.sem'
[[ $(stat -c %a '/srv/samba/custom FBI/FBI.csv') == 660 ]]
runuser -u ggc_user -- cat '/srv/samba/custom FBI/FBI.csv'
runuser -u ggc_user -- rm '/srv/samba/custom FBI/FBI.sem'
runuser -u spoke -- test -w '/srv/samba/custom FBI/FBI.csv'
echo 'Samba integration checks passed (SMB1 authentication, shared access, route commands).'
