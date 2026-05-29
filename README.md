# Prizmo

## Local development

### Prerequisites

- copy `env.template` to `.env`
- have Podman or Docker available
- for worktree hostname routing, have Caddy running with its admin API
- for worktree orchestration, install `worktrunk` (`wt`)

### Main branch

```bash
cp env.template .env
mix dev.up
```

This starts:

- Phoenix on [`localhost:4003`](http://localhost:4003)
- Postgres on `localhost:5435`
- SeaweedFS S3 on `localhost:4570`

Useful commands:

- `mix dev.down` — stop Phoenix and local services
- `tail -f tmp/phoenix.log` — follow Phoenix logs

### Worktrees

```bash
wt switch --create feature-auth
```

Worktrunk will:

- copy `.env` from the main worktree
- generate `.env.local` with branch-specific ports
- write `.server.port`
- run `mix dev.up`

Each worktree gets isolated local services and a Caddy route at:

- `https://main.prizmo.localhost`
- `https://feature-auth.prizmo.localhost`

Remove a worktree and stop its services with:

```bash
wt remove feature-auth
```

### Notes

- `mix setup` now delegates to `db.setup`, syncs usage rules, and builds assets
- `mix dev.up` is the preferred local entrypoint over running `mix phx.server` directly

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
