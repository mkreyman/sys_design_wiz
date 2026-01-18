import Config

config :sys_design_wiz,
  generators: [timestamp_type: :utc_datetime],
  # Use direct Anthropic HTTP client (better for web apps than CLI-based SDK)
  llm_client: SysDesignWiz.LLM.AnthropicClient

config :sys_design_wiz, SysDesignWizWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SysDesignWizWeb.ErrorHTML, json: SysDesignWizWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SysDesignWiz.PubSub,
  live_view: [signing_salt: "competition"]

config :sys_design_wiz, SysDesignWizWeb.Gettext, default_locale: "en"

config :esbuild,
  version: "0.17.11",
  sys_design_wiz: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.3",
  sys_design_wiz: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
