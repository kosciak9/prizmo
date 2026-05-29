# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :ash,
  allow_forbidden_field_for_relationships_by_default?: true,
  include_embedded_source_by_default?: false,
  show_keysets_for_all_actions?: false,
  default_page_type: :keyset,
  policies: [no_filter_static_forbidden_reads?: false],
  keep_read_action_loads_when_loading?: false,
  default_actions_require_atomic?: true,
  read_action_after_action_hooks_in_order?: true,
  bulk_actions_default_to_errors?: true,
  transaction_rollback_on_error?: true,
  redact_sensitive_values_in_errors?: true,
  known_types: [AshPostgres.Timestamptz, AshPostgres.TimestamptzUsec]

config :ash_oban, pro?: false

config :ash_typescript,
  output_file: "lib/prizmo_web/spa/lib/ash/generated/ash_rpc.ts",
  types_output_file: "lib/prizmo_web/spa/lib/ash/generated/ash_types.ts",
  run_endpoint: "/rpc/run",
  validate_endpoint: "/rpc/validate",
  input_field_formatter: :camel_case,
  output_field_formatter: :camel_case,
  require_tenant_parameters: false,
  generate_zod_schemas: false,
  generate_phx_channel_rpc_actions: false,
  generate_validation_functions: false,
  zod_import_path: "zod",
  zod_schema_suffix: "ZodSchema",
  phoenix_import_path: "phoenix"

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :prizmo, Oban,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Postgres,
  queues: [default: 10],
  repo: Prizmo.Repo,
  plugins: [{Oban.Plugins.Cron, []}]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :prizmo, Prizmo.Mailer, adapter: Swoosh.Adapters.Local

# Configure the endpoint
config :prizmo, PrizmoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PrizmoWeb.ErrorHTML, json: PrizmoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Prizmo.PubSub,
  live_view: [signing_salt: "HcfhF0dr"]

config :prizmo,
  ecto_repos: [Prizmo.Repo],
  generators: [timestamp_type: :utc_datetime],
  ash_domains: [Prizmo.Accounts],
  ash_authentication: [return_error_on_invalid_magic_link_token?: true]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :admin,
        :authentication,
        :token,
        :user_identity,
        :postgres,
        :resource,
        :code_interface,
        :actions,
        :policies,
        :pub_sub,
        :preparations,
        :changes,
        :validations,
        :multitenancy,
        :attributes,
        :relationships,
        :calculations,
        :aggregates,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:admin, :resources, :policies, :authorization, :domain, :execution]
    ]
  ]

config :volt, :format,
  print_width: 100,
  semi: false,
  single_quote: true,
  trailing_comma: :none,
  arrow_parens: :always

config :volt, :lint,
  plugins: [:typescript, :react],
  rules: %{"no-debugger" => :deny, "eqeqeq" => :deny}

config :volt,
  entry: ["lib/prizmo_web/spa/index.tsx"],
  root: "lib/prizmo_web/spa",
  outdir: "priv/static/assets",
  sources: ["**/*.{js,ts,jsx,tsx}"],
  ignore: ["node_modules/**", "vendor/**", "lib/ash/generated/**"],
  target: :es2020,
  sourcemap: :hidden,
  import_source: "react",
  plugins: [PrizmoWeb.VoltReactTanstackPlugin],
  resolve_dirs: [
    Path.expand("../deps", __DIR__),
    Path.expand("../_build/#{config_env()}", __DIR__),
    Mix.Project.build_path()
  ],
  # Import environment specific config. This must remain at the bottom
  # of this file so it overrides the configuration defined above.
  tailwind: [
    css: "lib/prizmo_web/spa/assets/css/app.css",
    sources: [
      %{base: "lib/prizmo_web", pattern: "**/*.{ex,heex}"},
      %{base: "lib/prizmo_web/spa", pattern: "**/*.{js,ts,jsx,tsx}"}
    ]
  ]

import_config "#{config_env()}.exs"
