# pmg_domain_mgmt

Deploy a self-contained Bash **management script** (plus a root-only
credentials file) onto a host so that host can manage **relay domains** on a
remote **Proxmox Mail Gateway (PMG)** through the PMG REST API. For a single
domain the script manages three things at once:

| Object             | PMG API endpoint           | Enabled by |
|--------------------|----------------------------|------------|
| Relay domain       | `/config/domains`          | always     |
| Transport map      | `/config/transport`        | `-t` flag  |
| DKIM signing       | `/config/dkim/domains`     | `-k` flag  |

The host running the script **does not have to be a PMG itself** — it can be
any automation host that can reach the PMG API.

> [!NOTE]
> This role is shared as a **personal reference**, not as a fully maintained
> open-source project. It was reworked **"vibe-coded"** — i.e. with substantial
> AI (LLM) assistance — and then reviewed and validated against the PMG 9.1
> source (`bash -n`, isolated `jq` tests, and a mock PMG API server). There are
> no guarantees regarding update frequency or compatibility with newer Proxmox
> versions. Treat it as a foundation to **adapt to your own environment**, and
> review it before any production use.

> [!WARNING]
> Provided **as-is, without warranty of any kind**. Use at your own risk. The
> script talks to a live mail gateway — test with `-C get` (read-only) and
> `--check --diff` before any write.

> AI assistants: read [`AI_CONTEXT.md`](AI_CONTEXT.md) before changing anything.

---

## Table of contents

- [How it works](#how-it-works)
- [Quick start](#quick-start)
- [What gets deployed](#what-gets-deployed)
- [Variable reference](#variable-reference)
- [Phase tags](#phase-tags)
- [Using the script](#using-the-script)
- [Optional: bootstrap the API user](#optional-bootstrap-the-api-user)
- [Examples](#examples)
- [Security notes](#security-notes)
- [Verification on the workstation](#verification-on-the-workstation)
- [Design decisions](#design-decisions)

---

## How it works

PMG has **no API tokens** for the configuration API, so the script uses the
classic ticket flow: it `POST`s the username + password to `/access/ticket`,
gets back a ticket and a CSRF token, then sends the ticket as a cookie and the
CSRF token as a header on every write (`POST`/`PUT`/`DELETE`).

JSON responses are parsed with **`jq`** (not `sed`/`awk`), and domain existence
is checked by **exact match** on the `domain` field — so `example.com` never
matches `notexample.com`.

The script holds **no secrets**. Connection details and the password live in a
separate config file deployed with mode `0600`; the script only sources it.

---

## Quick start

```yaml
# host_vars/<host>/vars.yml
pmg_domain_mgmt_host: "https://pmg.example.com:8006"
pmg_domain_mgmt_prox_username: "apiuser"
pmg_domain_mgmt_prox_username_realm: "pmg"
pmg_domain_mgmt_password: "{{ vault_pmg_domain_mgmt_password }}"
```

```bash
ansible-playbook site.yml -l <host> --tags pmg_domain_mgmt
```

Then, on the target host:

```bash
sudo /opt/pmg_domain_mgmt.sh -C get -d example.com
```

---

## What gets deployed

| Path                                          | Mode   | Contents                          |
|-----------------------------------------------|--------|-----------------------------------|
| `/opt/pmg_domain_mgmt.sh`                     | `0755` | the management script (no secret) |
| `/etc/pmg-domain-mgmt/`                       | `0750` | config directory                 |
| `/etc/pmg-domain-mgmt/pmg-domain-mgmt.conf`   | `0600` | host/user/**password**/TLS/defaults |

All paths, the owner and the modes are configurable (see below).

---

## Variable reference

Every variable is prefixed with the role name. Defaults live in
[`defaults/main.yml`](defaults/main.yml) with commented examples next to each
value — the table below is the summary.

### Connection (rendered into the credentials file)

| Variable | Default | Purpose |
|----------|---------|---------|
| `pmg_domain_mgmt_host` | `https://pmg.example.com:8006` | PMG API base URL (point at the master node) |
| `pmg_domain_mgmt_prox_username` | `apiuser` | API user name |
| `pmg_domain_mgmt_prox_username_realm` | `pmg` | Realm (`pmg`, `pam`, …) |
| `pmg_domain_mgmt_prox_username_full` | `apiuser@pmg` | Derived `user@realm` (don't set directly) |
| `pmg_domain_mgmt_password` | `{{ vault_… }}` | API password — **always from Vault** |
| `pmg_domain_mgmt_tls_verify` | `false` | Verify the PMG TLS cert (set `true` with a trusted cert) |

### Script behaviour

| Variable | Default | Purpose |
|----------|---------|---------|
| `pmg_domain_mgmt_default_command` | `get` | Command used when `-C` is omitted |
| `pmg_domain_mgmt_sleep_length` | `3` | Seconds before the post-change verify re-read (`0` = skip) |
| `pmg_domain_mgmt_transport_port` | `25` | Default transport port |
| `pmg_domain_mgmt_transport_protocol` | `smtp` | Default transport protocol (`smtp`/`lmtp`) |
| `pmg_domain_mgmt_transport_use_mx` | `0` | Default transport MX lookup (`0`/`1`) |

### On-host layout

| Variable | Default | Purpose |
|----------|---------|---------|
| `pmg_domain_mgmt_script_path` | `/opt` | Script directory |
| `pmg_domain_mgmt_script` | `pmg_domain_mgmt.sh` | Script filename |
| `pmg_domain_mgmt_config_dir` | `/etc/pmg-domain-mgmt` | Config directory |
| `pmg_domain_mgmt_config_file` | `…/pmg-domain-mgmt.conf` | Config/credentials file |
| `pmg_domain_mgmt_owner` | `root` | Owner of script + config (who can run/read it) |
| `pmg_domain_mgmt_group` | = owner | Group |
| `pmg_domain_mgmt_script_mode` | `0755` | Script mode |
| `pmg_domain_mgmt_config_mode` | `0600` | Config mode (secret) |
| `pmg_domain_mgmt_packages` | `[curl, jq]` | Packages installed on the host |

### Optional features (both default OFF)

| Variable | Default | Purpose |
|----------|---------|---------|
| `pmg_domain_mgmt_create_user` | `false` | Bootstrap the API user on a PMG via `pmgsh` |
| `pmg_domain_mgmt_create_user_host` | `{{ inventory_hostname }}` | PMG node the bootstrap runs on (default: the targeted host; override to delegate from an automation host) |
| `pmg_domain_mgmt_create_user_role` | `admin` | Role for the bootstrapped user |
| `pmg_domain_mgmt_selftest` | `false` | Run a read-only `get` after deploy to test connectivity |
| `pmg_domain_mgmt_selftest_domain` | `example.com` | Domain queried by the self-test |

---

## Phase tags

Run a slice of the role with a phase tag:

```bash
ansible-playbook site.yml -l <host> --tags pmg_domain_mgmt_deploy
```

| Tag | Runs |
|-----|------|
| `pmg_domain_mgmt` | everything |
| `pmg_domain_mgmt_packages` | install curl + jq |
| `pmg_domain_mgmt_user` | bootstrap the API user (opt-in) |
| `pmg_domain_mgmt_deploy` | credentials file + script |
| `pmg_domain_mgmt_selftest` | read-only connectivity test (opt-in) |

---

## Using the script

```text
pmg_domain_mgmt.sh -C <command> -d <domain> [options]
```

| Option | Long | Meaning |
|--------|------|---------|
| `-C` | `--command` | `get` \| `add` \| `update` \| `delete` |
| `-d` | `--domain` | Domain, e.g. `example.com` (**required**) |
| `-c` | `--comment` | Comment for domain/transport/DKIM (see warning below) |
| `-t` | `--transport` | Transport target host (FQDN/IP); enables transport handling |
| `-p` | `--port` | Transport port (default from config) |
| `-P` | `--protocol` | Transport protocol `smtp`/`lmtp` |
| `-m` | `--use-mx` | Transport MX lookup `0`/`1` |
| `-k` | `--dkim` | Enable DKIM signing (flag) |
| `-D` | `--debug` | Verbose output (raw API responses to stderr) |
| `--config` | | Use an alternate config file |
| `-h` | `--help` | Help |

Command semantics:

- **`get`** — read-only; reports domain, transport and DKIM state.
- **`add`** — ensures the domain (and any `-t`/`-k` extras) **exist**; never
  removes anything; leaves already-present entries untouched.
- **`update`** — ensures the domain exists and **updates** its comment, and the
  transport/DKIM entries when their flags are given. A missing entry is added.
- **`delete`** — removes the domain **and** its transport and DKIM entries,
  regardless of `-t`/`-k`.

> ⚠️ On **`update`**, an omitted `-c/--comment` sets the comment to empty, i.e.
> it clears any existing comment. Pass the comment you want to keep.

Connection details never go on the command line — they come from the config
file (or environment variables `PMG_HOST`, `PMG_USERNAME`, `PMG_PASSWORD`,
`PMG_TLS_VERIFY`, …, which take precedence over the file).

---

## Optional: bootstrap the API user

If you don't want to create the PMG API user by hand, enable the opt-in
bootstrap. It runs the local `pmgsh` CLI **on a PMG node** (authenticating
implicitly as `root@pam`, so no API password is needed), creating or updating
the user and (re)setting its password to the Vault value.

**Run the role directly against a PMG** (the play targets the PMG over SSH) and
the user is created on that host — no extra variables needed:

```yaml
pmg_domain_mgmt_create_user: true
pmg_domain_mgmt_create_user_role: "admin"   # admin = can manage domains
```

```bash
# create the user on the PMG (and skip the script deploy) via the phase tag:
ansible-playbook site.yml -l <pmg-host> --tags pmg_domain_mgmt_user
```

**Or delegate from a separate automation host** to a remote PMG by pointing
`pmg_domain_mgmt_create_user_host` at the PMG's inventory name:

```yaml
pmg_domain_mgmt_create_user: true
pmg_domain_mgmt_create_user_host: "pmg1"    # inventory name of a PMG node
```

The bootstrap tasks always run (or are delegated) on
`pmg_domain_mgmt_create_user_host`, which defaults to the host the play targets.

---

## Examples

### 1. Minimal — manage domains from an automation host

```yaml
# host_vars/<automation-host>/vars.yml
pmg_domain_mgmt_host: "https://pmg.example.com:8006"
pmg_domain_mgmt_prox_username: "apiuser"
pmg_domain_mgmt_password: "{{ vault_pmg_domain_mgmt_password }}"
```

### 2. Trusted certificate + run as a dedicated user (no sudo needed)

```yaml
pmg_domain_mgmt_host: "https://pmg.example.com:8006"
pmg_domain_mgmt_password: "{{ vault_pmg_domain_mgmt_password }}"
pmg_domain_mgmt_tls_verify: true            # PMG has an ACME/LE cert
pmg_domain_mgmt_owner: "automation"         # script+config owned by this user
```

```bash
# now runnable without sudo by the 'automation' user:
/opt/pmg_domain_mgmt.sh -C get -d example.com
```

### 3. Custom transport defaults + LMTP

```yaml
pmg_domain_mgmt_transport_port: 24
pmg_domain_mgmt_transport_protocol: "lmtp"
pmg_domain_mgmt_transport_use_mx: 0
```

### 4. Bootstrap the API user and self-test in one run

```yaml
pmg_domain_mgmt_create_user: true
pmg_domain_mgmt_create_user_host: "pmg1"
pmg_domain_mgmt_selftest: true
pmg_domain_mgmt_selftest_domain: "example.com"
```

### 5. Script invocations

```bash
# Read state (safe, read-only)
sudo /opt/pmg_domain_mgmt.sh -C get -d example.com

# Add a relay domain with a comment
sudo /opt/pmg_domain_mgmt.sh -C add -d example.com -c "ACME Corp"

# Add domain + transport (host:port, no MX) + DKIM
sudo /opt/pmg_domain_mgmt.sh -C add -d example.com -c "ACME Corp" \
     -t mail.example.com -p 25 -m 0 -k

# Update the transport target and comment
sudo /opt/pmg_domain_mgmt.sh -C update -d example.com -c "ACME Corp" \
     -t newmail.example.com

# Delete the domain and everything attached to it
sudo /opt/pmg_domain_mgmt.sh -C delete -d example.com

# Verbose troubleshooting
sudo /opt/pmg_domain_mgmt.sh -C get -d example.com -D
```

---

## Security notes

- **Secrets are isolated.** The password lives only in
  `/etc/pmg-domain-mgmt/pmg-domain-mgmt.conf` (`0600`). The script itself has no
  secret, so it can stay world-readable/executable. The deploy task that writes
  the config file uses `no_log: true`.
- **No credentials on the command line.** Connection details come from the
  config file or environment, never from `argv` (so they don't leak into the
  process list or shell history).
- **TLS verification is a first-class toggle** (`pmg_domain_mgmt_tls_verify`),
  not a hard-coded `curl -k`. Turn it on as soon as the PMG has a trusted cert.
- **Inputs are URL-encoded** (`curl --data-urlencode`), so comments containing
  spaces or `&` no longer corrupt the request.
- The bootstrap path passes the password to `pmgsh` via the `argv` form with
  `no_log`, and uses the server-side hashing `password` parameter instead of
  shelling out to `mkpasswd`.

---

## Verification on the workstation

You can syntax-check and dry-run the rendered script locally without touching a
PMG:

```bash
# syntax check
bash -n /opt/pmg_domain_mgmt.sh

# the script validates inputs before any network call:
PMG_HOST=https://x PMG_USERNAME=u PMG_PASSWORD=p \
  bash /opt/pmg_domain_mgmt.sh -C get -d bad_domain   # -> "not valid", rc=1
```

Roll out with `--check --diff` first to preview file changes.

---

## Design decisions

- **The self-test never mutates.** Connectivity is checked opt-in and read-only
  (`get`). A self-test that writes to the live PMG on every play would be a
  footgun, so the role deliberately does not do that.
- **Credentials live only in a `0600` file**, never in the (world-executable)
  script and never on the command line, so they don't leak into the process
  list or shell history.
- **`jq` JSON parsing + exact domain matching** — `example.com` never matches
  `notexample.com`.
- **`become: true` only where root is actually needed** (packages, writing
  `/etc` + `/opt`, `pmgsh`).
- **Transport `port`/`protocol`/`use_mx` are configurable**, and **TLS
  verification is a first-class toggle** rather than a hard-coded `curl -k`.
- The opt-in user bootstrap uses PMG's server-side `password` hashing, so it
  needs no `mkpasswd`.
