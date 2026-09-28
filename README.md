# Spoke onsite setup

Guided setup for a **new Raspberry Pi running Raspberry Pi OS Lite (64-bit)**.
Flash the OS, enable SSH, connect to the venue network, then run as your normal user:

```bash
curl -fsSL https://raw.githubusercontent.com/Spoke-Technologies/onsite-setup/main/install.sh -o onsite-setup.sh && bash onsite-setup.sh
```

The wizard asks for a device name, guides AWS sign-in, and asks for the deployment mode, Hub URL,
agent client ID and private key. It installs Java, Node.js and AWS CLI, provisions
Greengrass as a boot service, deploys the published onsite agent, and waits for
AWS to report deployment success. Then check the heartbeat and run a sync in Hub.

SSO defaults are filled automatically, with session name `<device-name>-setup`.
Press Enter to keep that session, approve browser sign-in and select your AWS account/role.

You need:

- A sudo-enabled user and outbound access to AWS, Hub and the venue's upstream system.
- AWS SSO access to the account hosting `com.spokehub.OnsiteAgent` in `ap-southeast-2`.
  The role needs [Greengrass provisioning permissions](https://docs.aws.amazon.com/greengrass/v2/developerguide/provision-minimal-iam-policy.html),
  plus permission to describe IoT things, list/describe components, create deployments
  and list effective deployments.
- A published agent release and artifact-bucket access for `GreengrassV2TokenExchangeRole`.
- A configured Hub member source. The wizard tells you when to click **Bootstrap Agent**
  and paste the client ID and single-line private key.

This public repository contains only the installer. Agent code and releases remain
in [spoke-hub](https://github.com/Spoke-Technologies/spoke-hub) and your AWS account.
Choose **iot** for commands over `spoke/onsite-agents`, or **fbi** for MAX file exports.
FBI prompts default to:

- Folder: `/srv/samba/fbi`
- Linux group: `fbi`
- Local database: `/var/lib/spoke-onsite/max-fbi-agent.sqlite`

All three can be changed. The wizard creates a missing group/folder, runs
`sudo usermod -aG <chosen-group> ggc_user`, checks folder access and restarts
Greengrass before deployment. Existing share ownership and permissions are preserved;
if access checks fail, fix permissions for the chosen group. FBI requires directory
write access to remove `FBI.sem`, plus readable exported files. Processed `FBI.csv`
files are retained. The database directory is created for `ggc_user` if missing.

Configure a MAX Gaming source with FBI live transport in Hub. Samba sharing and MAX
exports must already be configured separately; verify a real `FBI.csv`/`FBI.sem`
export reaches Hub after deployment.

Non-secret answers are saved in `~/.config/spoke-onsite/setup.env`. The private key
is sent to the device's Greengrass configuration; its temporary deployment file is
removed on exit. AWS CLI keeps its normal SSO cache. No credentials are embedded here.

The wizard refuses existing local Greengrass installations and existing AWS device
names. If provisioning partially fails, inspect the existing device before retrying;
it never deletes or replaces an installation. Logs:

```bash
sudo tail -n 100 -f /greengrass/v2/logs/greengrass.log
sudo tail -n 100 -f /greengrass/v2/logs/com.spokehub.OnsiteAgent.log
```

Development check (Bash, Node.js, jq and AWS CLI 2.37.4+): `bash test.sh`.
The SSO check uses a temporary config with no sign-in or AWS requests.
Hardware setup still requires a real Pi smoke test.
