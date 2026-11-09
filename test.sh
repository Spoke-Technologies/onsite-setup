#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
bash -n install.sh
source ./install.sh

# Exercise the real command against a temporary hosts file, without sudo or DNS.
(
  host_test_dir=$(mktemp -d)
  trap 'rm -rf -- "$host_test_dir"' EXIT
  export host_test_dir HOST_TEST_FAIL=''
  printf '127.0.0.1 localhost\n192.168.5.2 keep CSC-APIGATEWAY.ODY.CLOUD other # venue\n::1 csc-apigateway.ody.cloud # old IPv6\n192.168.5.3 csc-apigateway.ody.cloud.extra\n# retain this comment\n' >"$host_test_dir/hosts"
  cp "$host_test_dir/hosts" "$host_test_dir/original"
  uname() { echo Linux; }
  python3() { command python3 - "$2" "$3" "$host_test_dir/hosts"; }
  cmp() { command cmp "$1" "$host_test_dir/hosts" "$3"; }
  sudo() {
    printf '%s\n' "$*" >>"$host_test_dir/calls"
    local arg args=()
    for arg in "$@"; do
      [[ "$arg" != /etc/hosts ]] || arg="$host_test_dir/hosts"
      [[ "$arg" != /etc/hosts.spoke-backup.XXXXXX ]] || arg="$host_test_dir/backup.XXXXXX"
      args+=("$arg")
    done
    [[ "$1" != -v ]] || return 0
    if [[ "$HOST_TEST_FAIL" == backup && "$1 $2" == 'cp -p' ]]; then return 1; fi
    if [[ "$HOST_TEST_FAIL" == write && "$1" == cp && "$2" != -p ]]; then
      printf 'partial write\n' >"$host_test_dir/hosts"
      return 1
    fi
    "${args[@]}"
  }
  export -f uname python3 cmp sudo
  run_host_map() { bash -c 'source ./install.sh; main --host-map "$@"' _ "$@" </dev/null >"$host_test_dir/output" 2>&1; }
  run_host_map 192.168.5.140 csc-apigateway.ody.cloud
  command cmp "$host_test_dir/original" "$(find "$host_test_dir" -name 'backup.*')"
  command python3 - "$host_test_dir/hosts" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
assert text == ('127.0.0.1 localhost\n192.168.5.2\tkeep other # venue\n'
                '# old IPv6\n192.168.5.3 csc-apigateway.ody.cloud.extra\n'
                '# retain this comment\n192.168.5.140\tcsc-apigateway.ody.cloud\n')
PY
  cp "$host_test_dir/hosts" "$host_test_dir/expected"
  rm "$host_test_dir/calls"
  run_host_map 192.168.5.140 CSC-APIGATEWAY.ODY.CLOUD.
  command cmp "$host_test_dir/expected" "$host_test_dir/hosts"
  [[ ! -e "$host_test_dir/calls" ]]
  for hostname in '' https://csc-apigateway.ody.cloud 'bad host' '-bad.example' 'a..example' $'bad\nexample' 'example:443'; do
    if run_host_map 192.168.5.140 "$hostname"; then echo 'Accepted invalid hostname' >&2; exit 1; fi
  done
  for address in '' 999.1.1.1 192.168.5.140/24 '192.168.5.140 extra'; do
    if run_host_map "$address" csc-apigateway.ody.cloud; then echo 'Accepted invalid IP' >&2; exit 1; fi
  done
  if run_host_map 192.168.5.140; then exit 1; fi
  if run_host_map 192.168.5.140 csc-apigateway.ody.cloud extra; then exit 1; fi
  [[ ! -e "$host_test_dir/calls" ]]
  for HOST_TEST_FAIL in backup write; do
    if run_host_map 192.168.5.141 csc-apigateway.ody.cloud; then echo 'Ignored hosts write failure' >&2; exit 1; fi
    command cmp "$host_test_dir/expected" "$host_test_dir/hosts"
  done
  HOST_TEST_FAIL=''
  printf '127.0.0.1 localhost' >"$host_test_dir/hosts"
  run_host_map 192.168.5.141 csc-apigateway.ody.cloud
  [[ $(cat "$host_test_dir/hosts") == $'127.0.0.1 localhost\n192.168.5.141\tcsc-apigateway.ody.cloud' ]]
  [[ $(main --help) == *--host-map* ]]
)

# Add a route without touching real NetworkManager profiles or requiring a tty.
(
  route_test_dir=$(mktemp -d)
  trap 'rm -rf -- "$route_test_dir"' EXIT
  export route_test_dir ROUTE_TEST_FAIL='' ROUTE_TEST_UUID=12345678-1234-1234-1234-123456789abc ROUTE_TEST_DEVICE=eth0
  uname() { echo Linux; }
  nmcli() {
    printf 'query %s\n' "$*" >>"$route_test_dir/calls"
    [[ "$ROUTE_TEST_FAIL" != lookup ]] || return 1
    [[ "$*" == "-g GENERAL.CON-UUID device show $ROUTE_TEST_DEVICE" ]] || return 1
    printf '%s\n' "$ROUTE_TEST_UUID"
  }
  sudo() {
    printf 'sudo %s\n' "$*" >>"$route_test_dir/calls"
    case "$*" in
      -v) [[ "$ROUTE_TEST_FAIL" != auth ]] ;;
      "nmcli connection modify uuid $ROUTE_TEST_UUID +ipv4.routes 10.128.26.0/24 192.168.0.254") [[ "$ROUTE_TEST_FAIL" != save ]] ;;
      "nmcli device reapply $ROUTE_TEST_DEVICE") [[ "$ROUTE_TEST_FAIL" != apply ]] ;;
      *) return 1 ;;
    esac
  }
  export -f uname nmcli sudo
  run_route() {
    : >"$route_test_dir/calls"
    bash -c 'source ./install.sh; main --route-add "$@"' _ "$@" </dev/null >"$route_test_dir/output" 2>&1
  }
  run_route 10.128.26.0 255.255.255.0 192.168.0.254 eth0
  [[ $(cat "$route_test_dir/calls") == "query -g GENERAL.CON-UUID device show eth0
sudo -v
sudo nmcli connection modify uuid $ROUTE_TEST_UUID +ipv4.routes 10.128.26.0/24 192.168.0.254
sudo nmcli device reapply eth0" ]]
  grep -F 'Route saved and applied.' "$route_test_dir/output" >/dev/null
  ROUTE_TEST_DEVICE=wlan0 run_route 10.128.26.0 24 192.168.0.254 wlan0
  for args in '10.128.26.1 24 192.168.0.254 eth0' '10.128.26.0 255.0.255.0 192.168.0.254 eth0' '10.128.26.0 24 invalid eth0' '10.128.26.0 24 192.168.0.254 --bad' '10.128.26.0 24 192.168.0.254' '10.128.26.0 24 192.168.0.254 eth0 extra'; do
    if run_route $args; then echo 'Accepted invalid route arguments' >&2; exit 1; fi
    [[ ! -s "$route_test_dir/calls" ]]
  done
  for ROUTE_TEST_UUID in '' -- 000000000000000000000000000000000000; do
    if run_route 10.128.26.0 24 192.168.0.254 eth0; then echo 'Accepted an inactive/invalid connection' >&2; exit 1; fi
    if grep -F 'sudo ' "$route_test_dir/calls"; then exit 1; fi
  done
  ROUTE_TEST_UUID=12345678-1234-1234-1234-123456789abc
  for ROUTE_TEST_FAIL in lookup auth save apply; do
    if run_route 10.128.26.0 24 192.168.0.254 eth0; then echo "Ignored route failure: $ROUTE_TEST_FAIL" >&2; exit 1; fi
    if grep -F 'Route saved and applied.' "$route_test_dir/output"; then exit 1; fi
    if [[ "$ROUTE_TEST_FAIL" == apply ]]; then
      grep -F 'Route saved, but could not apply' "$route_test_dir/output" >/dev/null
    elif grep -F 'device reapply' "$route_test_dir/calls"; then exit 1; fi
  done
  [[ $(main --help) == *--route-add* ]]
)

# The read-only option must return before opening /dev/tty or starting setup.
(
  cat() {
    [[ $# -eq 1 && "$1" == /sys/class/net/eth0/address ]] || return 1
    printf '%s\n' "$TEST_MAC"
  }
  [[ $(TEST_MAC=dc:a6:32:01:23:45 main --eth-mac </dev/null) == 'Ethernet MAC (eth0): dc:a6:32:01:23:45' ]]
  for TEST_MAC in '' invalid dc:a6:32:01:23 00:00:00:00:00:00 $'dc:a6:32:01:23:45\nextra'; do
    if (main --eth-mac </dev/null) >/dev/null 2>&1; then
      echo 'Accepted an invalid Ethernet MAC address' >&2; exit 1
    fi
  done
  if (main --eth-mac extra) >/dev/null 2>&1; then
    echo 'Accepted extra MAC option arguments' >&2; exit 1
  fi
  cat() { return 1; }
  if (main --eth-mac </dev/null) >/dev/null 2>&1; then
    echo 'Reported success for a missing Ethernet interface' >&2; exit 1
  fi
  [[ $(main --help) == *--eth-mac* ]]
)

# Exercise Tailscale setup without installing packages or joining a tailnet.
(
  work=$(mktemp -d)
  trap 'rm -rf -- "$work"' EXIT
  export work TEST_FAIL='' TEST_INSTALLED=0 TEST_CONFIRM=yes
  export TEST_INITIAL_JSON='{"BackendState":"NeedsLogin"}'
  export TEST_FINAL_JSON='{"BackendState":"Running","Self":{"Tags":["tag:restricted"]}}'
  command() {
    if [[ "$*" == '-v tailscale' ]]; then
      [[ "$TEST_INSTALLED" == 1 || -f "$work/installed" ]]; return
    fi
    builtin command "$@"
  }
  curl() {
    echo curl >>"$work/calls"
    [[ "$TEST_FAIL" != curl ]] || return 1
    [[ "$*" == "-fsSL https://tailscale.com/install.sh -o $work/tailscale-install.sh" ]]
    touch "$work/tailscale-install.sh"
  }
  sudo() {
    printf '%s\n' "$*" >>"$work/calls"
    [[ "$TEST_FAIL" != "$*" ]] || return 1
    case "$*" in
      'apt-get update'|'apt-get install -y ca-certificates curl jq'|'systemctl enable --now tailscaled') ;;
      "sh $work/tailscale-install.sh") [[ -f "$work/tailscale-install.sh" ]]; touch "$work/installed" ;;
      'tailscale status --json')
        if [[ -f "$work/up" ]]; then printf '%s\n' "$TEST_FINAL_JSON"; else printf '%s\n' "$TEST_INITIAL_JSON"; fi ;;
      'tailscale up --advertise-tags=tag:restricted --timeout=5m') touch "$work/up" ;;
      'tailscale ip -4') echo 100.64.0.1 ;;
      *) return 1 ;;
    esac
  }
  export -f command curl sudo
  run_tailscale() {
    rm -f "$work/installed" "$work/up" "$work/calls" "$work/tailscale-install.sh"
    bash -c 'source ./install.sh; confirm() { [[ "$TEST_CONFIRM" == yes ]]; }; setup_tailscale' >"$work/output" 2>&1
  }
  run_tailscale
  grep -Fx 'systemctl enable --now tailscaled' "$work/calls" >/dev/null
  grep -Fx "sh $work/tailscale-install.sh" "$work/calls" >/dev/null
  grep -Fx 'tailscale up --advertise-tags=tag:restricted --timeout=5m' "$work/calls" >/dev/null
  grep -F '100.64.0.1' "$work/output" >/dev/null
  TEST_INSTALLED=1 TEST_INITIAL_JSON="$TEST_FINAL_JSON" run_tailscale
  if grep -E '^(curl|sh |tailscale up )' "$work/calls"; then exit 1; fi
  for TEST_FINAL_JSON in '{"BackendState":"Running","Self":{}}' '{"BackendState":"NeedsMachineAuth","Self":{"Tags":["tag:restricted"]}}' '{"BackendState":"Running","Self":{"Tags":["tag:other"]}}'; do
    if run_tailscale; then echo 'Accepted an unapproved or missing Tailscale tag' >&2; exit 1; fi
    if grep -F 'Setup complete' "$work/output"; then exit 1; fi
  done
  TEST_FINAL_JSON='{"BackendState":"Running","Self":{"Tags":["tag:restricted"]}}'
  for TEST_FAIL in 'apt-get update' 'apt-get install -y ca-certificates curl jq' curl "sh $work/tailscale-install.sh" 'systemctl enable --now tailscaled' 'tailscale status --json' 'tailscale up --advertise-tags=tag:restricted --timeout=5m' 'tailscale ip -4'; do
    if run_tailscale; then echo "Ignored Tailscale failure: $TEST_FAIL" >&2; exit 1; fi
    if grep -F 'Setup complete' "$work/output"; then exit 1; fi
  done
  TEST_CONFIRM=no run_tailscale
  [[ ! -f "$work/calls" ]]
  if (main --tailscale-only extra </dev/null) >/dev/null 2>&1; then exit 1; fi
  [[ $(main --help) == *--tailscale-only* ]]
)

# Use the real CLI against an isolated config: no sign-in or AWS requests.
if command -v aws >/dev/null; then
  (
    config_dir=$(mktemp -d)
    trap 'rm -rf -- "$config_dir"' EXIT
    export AWS_CONFIG_FILE="$config_dir/config" AWS_SHARED_CREDENTIALS_FILE="$config_dir/credentials"
    export AWS_PROFILE=spoke-onsite-setup THING_NAME=spoke-magpies
    # Start with no config/profile at all, as on a fresh Pi.
    configure_sso_defaults </dev/null
    aws configure set region us-east-1 --profile unrelated
    aws configure set sso_account_id 123456789012 --profile "$AWS_PROFILE"
    aws configure set sso_role_name Installer --profile "$AWS_PROFILE"
    configure_sso_defaults </dev/null
    [[ $(aws configure get sso_session --profile "$AWS_PROFILE") == spoke-magpies-setup ]]
    [[ $(aws configure get sso_account_id --profile "$AWS_PROFILE") == 123456789012 ]]
    [[ $(aws configure get sso_role_name --profile "$AWS_PROFILE") == Installer ]]
    [[ $(aws configure get region --profile unrelated) == us-east-1 ]]
    node -e '
      const fs = require("node:fs"), assert = require("node:assert/strict");
      const config = fs.readFileSync(process.env.AWS_CONFIG_FILE, "utf8");
      assert.equal(config.split("[sso-session spoke-magpies-setup]").length, 2);
      for (const field of ["sso_start_url = https://spoke.awsapps.com/start", "sso_region = ap-southeast-2", "sso_registration_scopes = sso:account:access"]) assert(config.includes(field));
    '
  )
else
  echo 'SSO config check skipped (AWS CLI is not installed).'
fi

# Exercise the install under the restrictive umask that caused root-only files.
(
  work=$(mktemp -d)
  export work
  trap 'rm -rf -- "$work"' EXIT
  umask 077
  unzip() {
    mkdir "$work/aws"
    printf '#!/bin/bash\nmkdir "$work/installed"\ntouch "$work/installed/aws"\n' >"$work/aws/install"
    chmod +x "$work/aws/install"
  }
  sudo() { "$@"; }
  install_aws_cli
  node -e '
    const fs = require("node:fs"), assert = require("node:assert/strict");
    const mode = path => fs.statSync(process.env.work + path).mode & 0o777;
    assert.equal(mode("/aws"), 0o755);
    assert.equal(mode("/installed"), 0o755);
    assert.equal(mode("/installed/aws"), 0o644);
  '
  [[ $(umask) == 0077 ]]
)

valid_name spoke-venue_01
for name in '' 'venue/pi' 'venue pi' '-bad;command' "$(printf '%129s' x)"; do
  if valid_name "$name"; then echo 'Accepted an invalid device name' >&2; exit 1; fi
done

(
  FBI_ROUTE_NETWORK=10.128.211.0 FBI_ROUTE_MASK=255.255.255.0 FBI_ROUTE_GATEWAY=192.168.70.225
  [[ $(route_cidr) == 10.128.211.0/24 ]]
  [[ $(FBI_ROUTE_MASK=24 route_cidr) == 10.128.211.0/24 ]]
  for mask in 255.0.255.0 33 garbage 0.0.0.255; do
    if (FBI_ROUTE_MASK=$mask route_cidr) >/dev/null 2>&1; then exit 1; fi
  done
  if (FBI_ROUTE_NETWORK=10.128.211.7 route_cidr) >/dev/null 2>&1; then exit 1; fi
  if (FBI_ROUTE_GATEWAY=999.1.1.1 route_cidr) >/dev/null 2>&1; then exit 1; fi
  config_dir=$(mktemp -d)
  trap 'rm -rf -- "$config_dir"' EXIT
  printf '[global]\nworkgroup = EXISTING\n[other]\npath = /srv/other\n' >"$config_dir/original"
  MAX_FBI_WATCH_DIR='/srv/custom FBI' FBI_GROUP=venue-fbi FBI_SHARE_NAME=fbi
  render_samba_config "$config_dir/original" >"$config_dir/first"
  grep -Fx '[fbi]' "$config_dir/first" >/dev/null
  FBI_SHARE_NAME=SPOKE-FBI
  render_samba_config "$config_dir/first" >"$config_dir/second"
  render_samba_config "$config_dir/second" >"$config_dir/third"
  [[ $(grep -c '^\[SPOKE-FBI\]$' "$config_dir/third") == 1 ]]
  [[ $(grep -c '^# BEGIN SPOKE FBI$' "$config_dir/second") == 1 ]]
  grep -Fx '[SPOKE-FBI]' "$config_dir/second" >/dev/null
  if grep -Fx '[fbi]' "$config_dir/second"; then exit 1; fi
  grep -Fx '[other]' "$config_dir/second" >/dev/null
  grep -Fx 'workgroup = EXISTING' "$config_dir/second" >/dev/null
  grep -Fx '   server min protocol = NT1' "$config_dir/second" >/dev/null
  grep -Fx '   path = /srv/custom FBI' "$config_dir/second" >/dev/null
  grep -Fx '   valid users = @venue-fbi' "$config_dir/second" >/dev/null
  if (FBI_SHARE_NAME=OTHER render_samba_config "$config_dir/original") >"$config_dir/collision" 2>/dev/null; then
    echo 'Overwrote an unrelated share' >&2; exit 1
  fi
  [[ ! -s "$config_dir/collision" ]]
)

# Exercise the shared prompt without Samba, sudo or a real venue route.
(
  config_dir=$(mktemp -d)
  trap 'rm -rf -- "$config_dir"' EXIT
  ENV_FILE="$config_dir/answers"
  MAX_FBI_WATCH_DIR=/srv/samba/fbi FBI_GROUP=fbi
  getent() { return 1; }
  realpath() { printf '%s\n' "${@: -1}"; }
  prompt_fbi_samba <<< $'\n\ntest-password\ntest-password\n' >/dev/null
  [[ "$FBI_SHARE_NAME" == fbi ]]
  [[ $(_existing FBI_SHARE_NAME) == fbi ]]
  prompt_fbi_samba <<< $'SPOKE-FBI\n\ntest-password\ntest-password\n' >"$config_dir/output"
  [[ "$FBI_SHARE_NAME" == SPOKE-FBI ]]
  [[ $(_existing FBI_SHARE_NAME) == SPOKE-FBI ]]
  grep -F '\\<Pi-IP>\SPOKE-FBI' "$config_dir/output" >/dev/null
  prompt_fbi_samba <<< $'\n\ntest-password\ntest-password\n' >/dev/null
  [[ "$FBI_SHARE_NAME" == SPOKE-FBI ]]
  for share in 'bad name' '/SPOKE-FBI' 'bad\name' 'bad]' 'bad#name' 'bad;name' $'bad\rname' '-bad' global GLOBAL homes HoMeS printers IPC\$ "$(printf '%081d' 0)"; do
    if (prompt_fbi_samba <<< "$share") >/dev/null 2>&1; then
      echo "Accepted invalid share name: $share" >&2; exit 1
    fi
    [[ $(_existing FBI_SHARE_NAME) == SPOKE-FBI ]]
  done
)

export THING_NAME=spoke-test THING_ARN=arn:aws:iot:ap-southeast-2:123456789012:thing/spoke-test
export COMPONENT_VERSION=0.2.1 HUB_BASE_URL=https://hub.example.com/api ONSITE_AGENT_CLIENT_ID=agent_test ONSITE_AGENT_TRANSPORT=iot
ONSITE_AGENT_PRIVATE_KEY=$(node -e 'process.stdout.write(require("node:crypto").generateKeyPairSync("ed25519").privateKey.export({format:"der",type:"pkcs8"}).toString("base64"))')
export ONSITE_AGENT_PRIVATE_KEY
validate_hub_credentials
deployment_json | jq -e '
  .targetArn == env.THING_ARN and
  (.components["com.spokehub.OnsiteAgent"] |
    .componentVersion == env.COMPONENT_VERSION and
    (.configurationUpdate.merge | fromjson |
      .OnsiteAgentPrivateKey == env.ONSITE_AGENT_PRIVATE_KEY and
      .HubBaseUrl == env.HUB_BASE_URL and .OnsiteAgentTransport == "iot" and
      .accessControl["aws.greengrass.ipc.mqttproxy"]["com.spokehub.OnsiteAgent:mqttproxy:1"].resources == ["spoke/onsite-agents/agent_test/commands"]))
' >/dev/null
(
  test_dir=$(mktemp -d)
  trap 'rm -rf -- "$test_dir"' EXIT
  ENV_FILE="$test_dir/answers"
  configure_transport <<< $'fbi\n\n\n\n' >/dev/null
  [[ "$FBI_GROUP" == fbi && "$MAX_FBI_WATCH_DIR" == /srv/samba/fbi ]]
  [[ "$MAX_FBI_LOCAL_DB_PATH" == /var/lib/spoke-onsite/max-fbi-agent.sqlite ]]
  configure_transport <<< $'fbi\n/srv/custom FBI\nvenue-fbi\n/var/lib/custom/queue.sqlite' >/dev/null
  [[ "$FBI_GROUP" == venue-fbi ]]
  deployment_json | jq -e '.components["com.spokehub.OnsiteAgent"].configurationUpdate.merge | fromjson |
    .OnsiteAgentTransport == "fbi" and .MaxFbiWatchDir == "/srv/custom FBI" and
    .MaxFbiLocalDbPath == "/var/lib/custom/queue.sqlite" and .MaxFbiDeleteProcessedFiles == "false"' >/dev/null
  if (configure_transport <<< $'fbi\nrelative/path\nfbi\n/var/lib/queue.sqlite') >/dev/null 2>&1; then
    echo 'Accepted a relative FBI path' >&2; exit 1
  fi
  if (configure_transport <<< $'fbi\n/srv/fbi\n--bad-group\n/var/lib/queue.sqlite') >/dev/null 2>&1; then
    echo 'Accepted an invalid group' >&2; exit 1
  fi
  # Exercise filesystem setup with privilege/account commands recorded, not run.
  MAX_FBI_WATCH_DIR="$test_dir/share with spaces"
  MAX_FBI_LOCAL_DB_PATH="$test_dir/database/queue.sqlite"
  getent() { return 1; }
  sudo() {
    printf '%s\n' "$*" >>"$test_dir/commands"
    case "$1" in
      groupadd|usermod|systemctl) return 0 ;;
      install) mkdir -p -- "${@: -1}" ;;
      -u) shift 2; "$@" ;;
      *) return 1 ;;
    esac
  }
  prepare_fbi_access
  [[ -d "$MAX_FBI_WATCH_DIR" && -d "$test_dir/database" ]]
  grep -Fx 'groupadd venue-fbi' "$test_dir/commands" >/dev/null
  grep -Fx 'usermod -aG venue-fbi ggc_user' "$test_dir/commands" >/dev/null
  grep -Fx 'systemctl restart greengrass' "$test_dir/commands" >/dev/null
  [[ -z $(ls -A "$MAX_FBI_WATCH_DIR") ]]
)
for url in http://hub.example.com/api https://user:pass@hub.example.com/api 'https://hub.example.com/api?key=secret'; do
  if (export HUB_BASE_URL="$url"; validate_hub_credentials) >/dev/null 2>&1; then
    echo 'Accepted an unsafe Hub URL' >&2; exit 1
  fi
done
if (export ONSITE_AGENT_PRIVATE_KEY=invalid; validate_hub_credentials) >/dev/null 2>&1; then
  echo 'Accepted an invalid private key' >&2; exit 1
fi

# Verify the AWS result for this deployment, not an older successful deployment.
export DEPLOYMENT_ID=new-deployment
aws() { printf '%s\n' "{\"effectiveDeployments\":[{\"deploymentId\":\"old\",\"coreDeviceExecutionStatus\":\"SUCCEEDED\"},{\"deploymentId\":\"new-deployment\",\"coreDeviceExecutionStatus\":\"$TEST_STATUS\"}]}"; }
# A successful terminal status must return without another polling sleep.
(
  sleep() { echo 'Polled again after a successful deployment' >&2; exit 1; }
  TEST_STATUS=SUCCEEDED wait_for_deployment
  TEST_STATUS=COMPLETED wait_for_deployment
)
for status in FAILED REJECTED TIMED_OUT CANCELED; do
  if (TEST_STATUS=$status wait_for_deployment) >/dev/null 2>&1; then
    echo 'Reported success for a failed deployment' >&2; exit 1
  fi
done
echo 'Installer checks passed.'
