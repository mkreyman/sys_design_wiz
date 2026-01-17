import Config

config :sys_design_wiz, SysDesignWizWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "test_secret_key_base_needs_to_be_at_least_64_bytes_long_for_security_purposes",
  server: false

# Use mock clients in tests
config :sys_design_wiz, :llm_client, SysDesignWiz.LLM.MockClient
config :sys_design_wiz, :spacex_client, SysDesignWiz.SpaceX.MockClient

# Configure ClaudeCode.Test adapter for stubbing SDK calls
config :claude_code, adapter: {ClaudeCode.Test, ClaudeCode}

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true
