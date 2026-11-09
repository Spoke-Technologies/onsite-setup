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

All three can be changed. FBI setup also installs Samba and prompts for a Windows
share name (default `fbi`), a dedicated login username (default `FBI`) and password.
The share name accepts 1–80 letters, digits, underscores or hyphens, starting with a
letter or digit; reserved names and names used by unrelated shares are rejected.
It shares the selected folder under that name,
enables SMBv1 (`NT1`) and NTLM authentication, and adds the Samba user, `ggc_user`
and the current login user (normally `spoke`) to the selected group.

The share tree is owned by the Samba user/group, with directories set to `2770` and
files to `0660`. New Samba files retain group read/write access. Existing unrelated
Samba settings are retained, and `smb.conf` is backed up before the managed FBI block
is installed. Firewall settings are not changed. Passwords are entered invisibly
and are not saved in the wizard's answers file.

For the optional route prompts, use the values from the venue's supplied Windows
route command as explained in [Add a persistent route](#add-a-persistent-route).
Leave the destination blank if no route is needed. The wizard saves the route on
the selected interface's active NetworkManager connection and applies it with
`nmcli device reapply`.

Configure a MAX Gaming source with FBI live transport in Hub. Connect from Windows
to `\\<Pi-IP>\<share-name>` with the Samba username/password. For example, enter
`SPOKE-FBI` at the Windows share name prompt to use `\\<Pi-IP>\SPOKE-FBI`.
The local folder can stay `/srv/samba/fbi`; it is separate from the share name.
Configure MAX to write
`FBI.csv` and `FBI.sem`, then verify an export reaches Hub. Reconnect SSH to pick up
the current user's new Linux group membership.

### Add Samba to an already-deployed Pi

This only configures the local share, group access and route; it does not provision
AWS or redeploy the agent. Keep the folder/database paths configured on your agent.
You can also use it to rename the managed share: enter the new Windows share name
and reconnect Windows/MAX using that name. The previous managed share name is
replaced, and the chosen name is saved for future runs (Enter keeps the saved name).

```bash
curl -fsSL https://raw.githubusercontent.com/Spoke-Technologies/onsite-setup/main/install.sh -o onsite-setup.sh && bash onsite-setup.sh --fbi-share-only
```

### Add a persistent route

If the venue gives you a Windows command such as:

```text
route add -p 10.128.26.0 mask 255.255.255.0 192.168.0.254
```

Use these values in the Pi wizard or standalone command:

| Supplied value | Meaning | Pi wizard prompt |
| --- | --- | --- |
| `10.128.26.0` | Destination network to reach | Destination network |
| `255.255.255.0` | Subnet mask, equivalent to prefix length `24` | Subnet mask or prefix length |
| `192.168.0.254` | Gateway on the Pi's local network | Gateway IP |
| `-p` | Keep the route after reboot | Automatic with this command |

Run this on the Pi, before or after agent deployment:

```bash
curl -fsSL https://raw.githubusercontent.com/Spoke-Technologies/onsite-setup/main/install.sh -o onsite-setup.sh && bash onsite-setup.sh --route-add 10.128.26.0 255.255.255.0 192.168.0.254 eth0
```

The argument order is `--route-add NETWORK MASK GATEWAY INTERFACE`. Enter only
the values; omit the Windows words `route add -p` and `mask`. You can use `24`
instead of `255.255.255.0`. Replace `eth0` with the connected interface that can
reach the gateway, for example `wlan0` for Wi-Fi. Check interfaces and addresses:

```bash
nmcli device status
ip -4 address show dev eth0
```

This example sends traffic for `10.128.26.0/24` through `192.168.0.254`. The
gateway must be reachable on the selected interface's local network. The command
requires Python 3, NetworkManager and sudo. It saves the route in the interface's
active connection profile, adds it alongside existing routes, and applies it
immediately without taking the interface down. The route persists when that
profile reconnects, including after reboot. Repeating the same route does not add
duplicates. It does not provision AWS, configure Samba or redeploy the agent.
See the [NetworkManager command reference](https://networkmanager.dev/docs/api/latest/nmcli.html).

Verify the route and the path to an address inside the destination network:

```bash
ip -4 route show 10.128.26.0/24
ip -4 route get 10.128.26.1
```

The selected path should include `via 192.168.0.254 dev eth0`. Use an actual
venue server IP when checking its path. A saved route does not prove that the
server is online or that the venue firewall allows access. If saving succeeds
but applying fails, the command reports that separately; fix the reported error
and rerun it.

### Map a hostname to a local IP when DNS is unavailable

Run this on the Pi to make `https://csc-apigateway.ody.cloud` connect to
`192.168.5.140`, before or after deploying the agent:

```bash
curl -fsSL https://raw.githubusercontent.com/Spoke-Technologies/onsite-setup/main/install.sh -o onsite-setup.sh && bash onsite-setup.sh --host-map 192.168.5.140 csc-apigateway.ody.cloud
```

Use an IPv4 address and a hostname without `https://`, a port or a path. This
backs up `/etc/hosts`, replaces existing entries for that exact hostname (including
IPv6 entries), and preserves other hostnames, aliases and comments. Repeating the
same command does not add duplicate entries. It requires Python 3 and sudo for
changes, and does not provision AWS or redeploy the agent.

The override persists across reboots and only affects this Pi. Keep using the
HTTPS URL so the server receives the correct hostname; the server must still
present a trusted certificate valid for that hostname. Restart the calling
application if it has cached the old address. To remove the override after DNS
is fixed, run `sudoedit /etc/hosts` and delete the added hostname entry.

Verify the Pi's system resolver and HTTPS connection:

```bash
getent ahostsv4 csc-apigateway.ody.cloud
curl -I --connect-timeout 10 https://csc-apigateway.ody.cloud
```

### Fetch the Ethernet MAC address

Run this on the Pi to display its `eth0` MAC address, for example for venue network
registration. It works before or after deployment, without sudo, AWS sign-in or
any setup changes. The Ethernet cable does not need to be connected.

```bash
curl -fsSL https://raw.githubusercontent.com/Spoke-Technologies/onsite-setup/main/install.sh -o onsite-setup.sh && bash onsite-setup.sh --eth-mac
```

The output is `Ethernet MAC (eth0): <mac-address>`. A missing interface or invalid
address reports an error and exits unsuccessfully.

Non-secret answers are saved in `~/.config/spoke-onsite/setup.env`. The private key
is sent to the device's Greengrass configuration; its temporary deployment file is
removed on exit. AWS CLI keeps its normal SSO cache. No credentials are embedded here.

### Set up Tailscale remote access

Run as your normal sudo-enabled Pi user, before or after deploying the onsite agent:

```bash
curl -fsSL https://raw.githubusercontent.com/Spoke-Technologies/onsite-setup/main/install.sh -o onsite-setup.sh && bash onsite-setup.sh --tailscale-only
```

This installs Tailscale using its [official Linux installer](https://tailscale.com/docs/install/linux),
enables `tailscaled` on boot and connects the Pi with `tag:restricted`. Open the
login URL printed in the terminal on your laptop and sign in. If device approval
is enabled, approve the Pi in the Tailscale admin console. Sign-in/approval has a
five-minute timeout; rerun the command if needed. Setup verifies the connection
and assigned tag, then prints the Pi's Tailscale IPv4 address. Existing connected
devices already carrying `tag:restricted` keep their current session.

Your tailnet must already [define `tag:restricted` and its owners](https://tailscale.com/docs/features/tags).
The signing-in account must be allowed to assign it. **The tag name alone does
not restrict access**: configure your tailnet's grants/ACLs for this tag. Tagging
changes a user-owned device to a tagged server identity.

This command sets up access to the Pi itself using its existing services, including
normal SSH. It does not enable Tailscale SSH, subnet routing or exit-node routing,
and does not provision AWS or redeploy the agent. Existing custom Tailscale
settings are not reset: if the CLI asks you to include existing flags, follow its
printed command before rerunning the wizard.

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
