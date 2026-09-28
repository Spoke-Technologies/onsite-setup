#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
bash -n install.sh
source ./install.sh

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
