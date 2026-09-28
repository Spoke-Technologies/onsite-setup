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

All three can be changed. FBI setup also installs Samba and prompts for a dedicated
login username (default `FBI`) and password. It shares the selected folder as `fbi`,
enables SMBv1 (`NT1`) and NTLM authentication, and adds the Samba user, `ggc_user`
and the current login user (normally `spoke`) to the selected group.

The share tree is owned by the Samba user/group, with directories set to `2770` and
files to `0660`. New Samba files retain group read/write access. Existing unrelated
Samba settings are retained, and `smb.conf` is backed up before the managed FBI block
is installed. Firewall settings are not changed. Passwords are entered invisibly
and are not saved in the wizard's answers file.

For the route, enter the destination network IP, subnet mask (or prefix length),
gateway IP and interface. Leave the destination blank if no route is needed. The
wizard saves the route on that interface's active NetworkManager connection and
applies it without disconnecting the interface. For example:

```bash
sudo nmcli connection modify uuid <connection-uuid> +ipv4.routes "10.128.211.0/24 192.168.70.225"
sudo nmcli device reapply eth0
```

Configure a MAX Gaming source with FBI live transport in Hub. Connect from Windows
to `\\<Pi-IP>\fbi` with the Samba username/password. Configure MAX to write
`FBI.csv` and `FBI.sem`, then verify an export reaches Hub. Reconnect SSH to pick up
the current user's new Linux group membership.

### Add Samba to an already-deployed Pi

This only configures the local share, group access and route; it does not provision
AWS or redeploy the agent. Keep the folder/database paths configured on your agent.

```bash
curl -fsSL https://raw.githubusercontent.com/Spoke-Technologies/onsite-setup/main/install.sh -o onsite-setup.sh && bash onsite-setup.sh --fbi-share-only
```

Non-secret answers are saved in `~/.config/spoke-onsite/setup.env`. The private key
is sent to the device's Greengrass configuration; its temporary deployment file is
removed on exit. AWS CLI keeps its normal SSO cache. No credentials are embedded here.

Full deployment refuses existing local Greengrass installations and existing AWS device
names; use `--fbi-share-only` for an already-deployed Pi. If provisioning partially fails, inspect the existing device before retrying;
it never deletes or replaces an installation. Logs:

```bash
sudo tail -n 100 -f /greengrass/v2/logs/greengrass.log
sudo tail -n 100 -f /greengrass/v2/logs/com.spokehub.OnsiteAgent.log
```

Development check (Bash, Node.js, Python 3, jq and AWS CLI 2.37.4+): `bash test.sh`.
The SSO check uses a temporary config with no sign-in or AWS requests.
Samba integration check in a disposable Linux container:

```bash
docker run --rm -v "$PWD:/src:ro" debian:trixie-slim bash -c 'apt-get update -qq && apt-get install -y -qq --no-install-recommends samba smbclient python3 sudo && bash /src/test-samba.sh'
```

This checks SMBv1 authentication and real filesystem permissions; service and route
commands are stubbed inside the container. Live NetworkManager routing still needs
a real Pi check.
