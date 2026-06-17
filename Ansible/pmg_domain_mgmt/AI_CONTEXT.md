# pmg_domain_mgmt — AI context

Context and invariants for AI assistants working on this role. Read this before
changing anything. Human-facing usage docs live in [`README.md`](README.md).

## Purpose

Deploy a self-contained Bash script + a root-only credentials file onto a host
so it can manage **relay domains** (the domain entry, its transport map entry,
and DKIM signing) on a **remote Proxmox Mail Gateway** via the PMG REST API.
The host running the script is usually **not** the PMG — it is typically an
automation host that talks to a separate PMG over the API.

## Hard facts about the PMG API (verified against pmg-api master source)

- **No API tokens.** Unlike PVE, PMG's config API has no token mechanism. The
  only auth is the ticket flow: `POST username+password` to
  `/api2/json/access/ticket` → `{data:{ticket, CSRFPreventionToken}}`; then send
  `Cookie: PMGAuthCookie=<ticket>` and header `CSRFPreventionToken: <csrf>` on
  every write. (The "API token" strings in the docs are about PBS backup, not
  this API.) Don't "modernise" this to tokens — they don't exist.
- Endpoints used (all under `/api2/json`), each is `{data: …}`:
  - `/config/domains` — GET list / POST create / `…/{domain}` GET,PUT,DELETE.
    POST/PUT take `domain`, `comment`.
  - `/config/transport` — same shape. POST/PUT take `domain`, `host`,
    `protocol` (smtp|lmtp, default smtp), `port` (default 25), `use_mx`
    (bool, default 1), `comment`.
  - `/config/dkim/domains` — same shape as domains (`domain`, `comment`).
  - List endpoints return an array of objects with a `.domain` key → used for
    **exact-match** existence checks.
- `POST /access/users` accepts a plaintext `password` and hashes it server-side
  (`encrypt_pw`). `PUT /access/users/{id}` REJECTS `password` ("use
  /access/password"), so password changes on an existing user go through
  `PUT /access/password`. That's why the bootstrap uses `--password` on create
  and the `/access/password` endpoint on update — and why `mkpasswd` is gone.

## Hard invariants — do NOT break these

1. **The script must contain no secret.** Credentials live only in the `0600`
   config file (`/etc/pmg-domain-mgmt/pmg-domain-mgmt.conf`), which the script
   sources. The deploy task for it uses `no_log: true`. Keep this split.
2. **The self-test must never mutate.** It stays opt-in
   (`pmg_domain_mgmt_selftest`, default false) and read-only (`get`). A self-test
   that writes to the live PMG on every play (e.g. an `update`) is a footgun and
   must not be reintroduced.
3. **Don't gratuitously rename the public vars** `pmg_domain_mgmt_host`,
   `pmg_domain_mgmt_prox_username`, `pmg_domain_mgmt_prox_username_realm`,
   `pmg_domain_mgmt_password` — they are the role's API; renaming them means
   migrating every inventory that sets them.
4. **Exact domain matching only.** Existence is `jq 'any(.data[]?; .domain==$d)'`
   — never a substring/`grep` test (that matched `notexample.com` for
   `example.com` in the old script).
5. **`become: true` only where root is needed** (packages, writing `/etc` +
   `/opt`, `pmgsh`). The self-test uses `become_user` = owner so it can read the
   `0600` file as whoever owns it.
6. **Never connect to managed hosts from the workstation.** Build + lint +
   render here only. Validate the script with `bash -n` and the mock-server
   pattern. The maintainer rolls out (usually `--check --diff` first) and does
   the git commit/push/pull.

## House-style conventions

- Var prefix = role name: every variable starts with `pmg_domain_mgmt_`.
- Task names: `pmg_domain_mgmt | <description>`.
- Every task tagged `pmg_domain_mgmt` + a phase tag
  (`_packages` / `_user` / `_deploy` / `_selftest`).
- FQCN for all builtins (`ansible.builtin.*`).
- Defaults show optional values as commented examples; English docs/comments,
  German chat with the maintainer.
- `pmgsh` calls use the `command` `argv` form (no shell) so passwords and
  `user@realm` strings need no quoting gymnastics.

## File map

- `tasks/main.yml` — orchestration (`import_tasks` 00→30, with the opt-in gates).
- `tasks/00_packages.yml` — install `curl` + `jq` (`state: present`).
- `tasks/10_api_user.yml` — OPT-IN PMG user bootstrap via `pmgsh`, run on
  `pmg_domain_mgmt_create_user_host` (default: the targeted host, so running the
  role against a PMG creates the user there; override to delegate from an
  automation host to a remote PMG).
- `tasks/20_deploy.yml` — config dir, `0600` credentials file (no_log), script.
- `tasks/30_selftest.yml` — OPT-IN read-only `get` connectivity check.
- `templates/pmg_domain_mgmt.sh.j2` — the management script (the real logic).
- `templates/pmg-domain-mgmt.conf.j2` — sourced `VAR='value'` credentials file;
  values are `| quote`-d for bash safety.
- `defaults/main.yml` — all tunables with inline docs + commented alternatives.
- `meta/main.yml` — galaxy metadata.

## Script model (templates/pmg_domain_mgmt.sh.j2)

- `set -uo pipefail` (NOT `-e`: curl results are inspected explicitly).
- Config precedence: built-in defaults < config file < pre-set environment
  (`load_config` snapshots env host/user/pass and restores them after sourcing)
  < CLI flags. `--config` / `PMG_CONFIG` choose the file.
- `api METHOD PATH [k=v …]` → curl wrapper; appends `-w '\n%{http_code}'`;
  `api_split` separates body/status into `API_BODY`/`API_STATUS`; `api_ok`
  checks 2xx. Writes carry the cookie + CSRF header. `--data-urlencode` is used
  for all fields (comments with spaces/`&` are safe).
- Commands: `get` (read-only report), `add`/`update` via `cmd_upsert` (add =
  ensure-present, update = ensure-present + overwrite fields), `delete` removes
  domain+transport+DKIM. A post-change `verify` re-reads after
  `PMG_SLEEP_LENGTH`s.
- TLS: `curl -k` added only when `PMG_TLS_VERIFY` != true.

## Known trade-offs / open follow-ups

- The bootstrap "set password" task reports `changed` every run by design
  (PMG has no idempotent password-set). It only runs in the opt-in path; fine
  for bootstrap. If this ever needs to be idempotent, gate it behind an extra
  flag.
- `from_json` on `pmgsh get /access/users` assumes clean JSON on stdout (true
  for `pmgsh`). If a future PMG version prints banners, parse more defensively.
- Could not be tested against a live PMG from the workstation (no SSH). It was
  validated with `bash -n`, isolated `jq` tests, and a Python mock PMG server
  exercising login + get + add(+transport). Maintainer should `--check --diff`
  then run a real `-C get` before trusting writes.
