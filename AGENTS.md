Prizmo is a Phoenix/Ash application with a React SPA built by Volt.

## Development server

When running, assume the local application and required services are managed
through `mix dev.up` or `wt` (`worktrunk`). Parallel worktrees run on the same
host, so they use different ports stored in `.env.local` and `.server.port`.

**Accessing the dev server:**

- Check `.server.port` for the current Phoenix port, for example `http://localhost:4003`
- Use `mix dev.up` to start local services and `mix dev.down` to stop them
- Worktrunk generates `.env.local` with hashed ports for feature branches
- The default local domain is `prizmo.localhost`; worktrees use `{branch}.prizmo.localhost`
- Tidewave MCP should be available at `http://localhost:{PORT}/tidewave/mcp`

Avoid starting or restarting shared local servers blindly. You can interfere
with other active worktrees if you kill the wrong process.

## Project guidelines

- Use `mix check` when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

## Quality gate

`mix check` is the canonical local and CI quality gate. It runs:

1. `mix format`
2. `mix sobelow --config --compact --private`
3. `mix compile --warnings-as-errors`
4. `mix deps.unlock --check-unused`
5. `mix xref graph --label compile-connected --fail-above 50`
6. `mix check.filenames`
7. `mix check.service_images`
8. `mix ash_typescript.codegen --check`
9. `mix credo --strict`
10. `mix dialyzer`
11. `mix test`

Use `mix check --no-test` only when tests are being run separately. Use
`mix check --verbose` when you need full output for debugging.

## Commit policy

- Commit autonomously after each atomic change once the relevant verification passes.
- Before committing, inspect `git status`, `git diff`, and recent history; stage only the intended files and leave unrelated work untouched.
- Use Conventional Commit style. For knowledge-base/wiki-only documentation changes, use the `docs` type with `wiki` scope, for example `docs(wiki): capture renderer research`.
- If a code change also updates wiki/log documentation, commit those docs with the related code change instead of making a separate docs-only commit.

## Frontend

- Product UI lives in the Volt React SPA under `lib/prizmo_web/spa/`.
- Root JavaScript/TypeScript configuration lives at the repository root.
- Use `npm ci` via `mix assets.setup`; do not add a second package manager workflow.
- Generated AshTypescript files live under `lib/prizmo_web/spa/lib/ash/generated/` and must stay in sync with Ash resources.

## Ash migrations

- Prefer Ash-generated migrations and snapshots for resource changes.
- Do not hand-edit generated migrations unless the generated SQL is demonstrably wrong or incomplete.
- After changing Ash resources, run the appropriate Ash migration/codegen tasks and verify snapshots are updated intentionally.

## Sobelow findings

- Fix Sobelow findings when possible.
- If a finding is intentionally safe, add a narrow `sobelow_skip` with a clear reason near the code being skipped.

## Repository boundaries

- Keep generated runtime data, local uploads, credentials, and dependency caches out of git.
- Use `/tmp/opencode` for scratch work outside the repository.
- Verify APIs against the installed dependency versions before relying on examples from the internet.


<!-- usage-rules-start -->
<!-- phoenix:ecto-start -->
## phoenix:ecto usage
[phoenix:ecto usage rules](deps/phoenix/usage-rules/ecto.md)
<!-- phoenix:ecto-end -->
<!-- phoenix:html-start -->
## phoenix:html usage
[phoenix:html usage rules](deps/phoenix/usage-rules/html.md)
<!-- phoenix:html-end -->
<!-- phoenix:liveview-start -->
## phoenix:liveview usage
[phoenix:liveview usage rules](deps/phoenix/usage-rules/liveview.md)
<!-- phoenix:liveview-end -->
<!-- phoenix:phoenix-start -->
## phoenix:phoenix usage
[phoenix:phoenix usage rules](deps/phoenix/usage-rules/phoenix.md)
<!-- phoenix:phoenix-end -->
<!-- ash-start -->
## ash usage
_A declarative, extensible framework for building Elixir applications._

[ash usage rules](deps/ash/usage-rules.md)
<!-- ash-end -->
<!-- ash:actions-start -->
## ash:actions usage
[ash:actions usage rules](deps/ash/usage-rules/actions.md)
<!-- ash:actions-end -->
<!-- ash:aggregates-start -->
## ash:aggregates usage
[ash:aggregates usage rules](deps/ash/usage-rules/aggregates.md)
<!-- ash:aggregates-end -->
<!-- ash:authorization-start -->
## ash:authorization usage
[ash:authorization usage rules](deps/ash/usage-rules/authorization.md)
<!-- ash:authorization-end -->
<!-- ash:calculations-start -->
## ash:calculations usage
[ash:calculations usage rules](deps/ash/usage-rules/calculations.md)
<!-- ash:calculations-end -->
<!-- ash:code_interfaces-start -->
## ash:code_interfaces usage
[ash:code_interfaces usage rules](deps/ash/usage-rules/code_interfaces.md)
<!-- ash:code_interfaces-end -->
<!-- ash:code_structure-start -->
## ash:code_structure usage
[ash:code_structure usage rules](deps/ash/usage-rules/code_structure.md)
<!-- ash:code_structure-end -->
<!-- ash:data_layers-start -->
## ash:data_layers usage
[ash:data_layers usage rules](deps/ash/usage-rules/data_layers.md)
<!-- ash:data_layers-end -->
<!-- ash:exist_expressions-start -->
## ash:exist_expressions usage
[ash:exist_expressions usage rules](deps/ash/usage-rules/exist_expressions.md)
<!-- ash:exist_expressions-end -->
<!-- ash:generating_code-start -->
## ash:generating_code usage
[ash:generating_code usage rules](deps/ash/usage-rules/generating_code.md)
<!-- ash:generating_code-end -->
<!-- ash:migrations-start -->
## ash:migrations usage
[ash:migrations usage rules](deps/ash/usage-rules/migrations.md)
<!-- ash:migrations-end -->
<!-- ash:query_filter-start -->
## ash:query_filter usage
[ash:query_filter usage rules](deps/ash/usage-rules/query_filter.md)
<!-- ash:query_filter-end -->
<!-- ash:querying_data-start -->
## ash:querying_data usage
[ash:querying_data usage rules](deps/ash/usage-rules/querying_data.md)
<!-- ash:querying_data-end -->
<!-- ash:relationships-start -->
## ash:relationships usage
[ash:relationships usage rules](deps/ash/usage-rules/relationships.md)
<!-- ash:relationships-end -->
<!-- ash:testing-start -->
## ash:testing usage
[ash:testing usage rules](deps/ash/usage-rules/testing.md)
<!-- ash:testing-end -->
<!-- ash_postgres-start -->
## ash_postgres usage
_The PostgreSQL data layer for Ash Framework_

[ash_postgres usage rules](deps/ash_postgres/usage-rules.md)
<!-- ash_postgres-end -->
<!-- ash_postgres:advanced_features-start -->
## ash_postgres:advanced_features usage
[ash_postgres:advanced_features usage rules](deps/ash_postgres/usage-rules/advanced_features.md)
<!-- ash_postgres:advanced_features-end -->
<!-- ash_postgres:best_practices-start -->
## ash_postgres:best_practices usage
[ash_postgres:best_practices usage rules](deps/ash_postgres/usage-rules/best_practices.md)
<!-- ash_postgres:best_practices-end -->
<!-- ash_postgres:check_constraints-start -->
## ash_postgres:check_constraints usage
[ash_postgres:check_constraints usage rules](deps/ash_postgres/usage-rules/check_constraints.md)
<!-- ash_postgres:check_constraints-end -->
<!-- ash_postgres:configuration-start -->
## ash_postgres:configuration usage
[ash_postgres:configuration usage rules](deps/ash_postgres/usage-rules/configuration.md)
<!-- ash_postgres:configuration-end -->
<!-- ash_postgres:custom_indexes-start -->
## ash_postgres:custom_indexes usage
[ash_postgres:custom_indexes usage rules](deps/ash_postgres/usage-rules/custom_indexes.md)
<!-- ash_postgres:custom_indexes-end -->
<!-- ash_postgres:custom_sql_statements-start -->
## ash_postgres:custom_sql_statements usage
[ash_postgres:custom_sql_statements usage rules](deps/ash_postgres/usage-rules/custom_sql_statements.md)
<!-- ash_postgres:custom_sql_statements-end -->
<!-- ash_postgres:foreign_keys-start -->
## ash_postgres:foreign_keys usage
[ash_postgres:foreign_keys usage rules](deps/ash_postgres/usage-rules/foreign_keys.md)
<!-- ash_postgres:foreign_keys-end -->
<!-- ash_postgres:migrations-start -->
## ash_postgres:migrations usage
[ash_postgres:migrations usage rules](deps/ash_postgres/usage-rules/migrations.md)
<!-- ash_postgres:migrations-end -->
<!-- ash_postgres:multitenancy-start -->
## ash_postgres:multitenancy usage
[ash_postgres:multitenancy usage rules](deps/ash_postgres/usage-rules/multitenancy.md)
<!-- ash_postgres:multitenancy-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
[usage_rules:elixir usage rules](deps/usage_rules/usage-rules/elixir.md)
<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
[usage_rules:otp usage rules](deps/usage_rules/usage-rules/otp.md)
<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
