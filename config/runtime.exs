import Config

# Start server when PHX_SERVER is set (used by Fly.io)
if System.get_env("PHX_SERVER") do
  config :sys_design_wiz, SysDesignWizWeb.Endpoint, server: true
end

# SQLite database path - use /app/data in production (Fly.io volume mount)
if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      "/app/data/sessions.db"

  config :sys_design_wiz, SysDesignWiz.Repo,
    database: database_path,
    pool_size: 5
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "localhost"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :sys_design_wiz, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :sys_design_wiz, SysDesignWizWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
end

# Anthropic API Configuration
# Required for the LLM client in production
if config_env() == :prod do
  anthropic_api_key =
    System.get_env("ANTHROPIC_API_KEY") ||
      raise """
      environment variable ANTHROPIC_API_KEY is missing.
      Get your API key from https://console.anthropic.com/
      """

  config :sys_design_wiz,
    anthropic_api_key: anthropic_api_key
end
