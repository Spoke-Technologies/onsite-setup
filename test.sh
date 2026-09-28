#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
bash -n install.sh
source ./install.sh

valid_name spoke-venue_01
for name in '' 'venue/pi' 'venue pi' '-bad;command' "$(printf '%129s' x)"; do
  if valid_name "$name"; then echo 'Accepted an invalid device name' >&2; exit 1; fi
done

export THING_NAME=spoke-test THING_ARN=arn:aws:iot:ap-southeast-2:123456789012:thing/spoke-test
export COMPONENT_VERSION=0.2.1 HUB_BASE_URL=https://hub.example.com/api ONSITE_AGENT_CLIENT_ID=agent_test
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
TEST_STATUS=SUCCEEDED wait_for_deployment
for status in FAILED REJECTED TIMED_OUT CANCELED; do
  if (TEST_STATUS=$status wait_for_deployment) >/dev/null 2>&1; then
    echo 'Reported success for a failed deployment' >&2; exit 1
  fi
done
echo 'Installer checks passed.'
