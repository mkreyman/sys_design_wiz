import Config

# Start server when PHX_SERVER is set (used by Fly.io)
if System.get_env("PHX_SERVER") do
  config :sys_design_wiz, SysDesignWizWeb.Endpoint, server: true
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

# Claude Code SDK Configuration
#
# The Claude Code SDK handles authentication automatically via:
# 1. Claude subscription (authenticate via `claude` CLI then `/login`)
# 2. ANTHROPIC_API_KEY environment variable
#
# No additional configuration required here - the SDK reads from environment.

# Legacy OpenAI support (optional, for backwards compatibility)
if config_env() != :test do
  if api_key = System.get_env("OPENAI_API_KEY") do
    config :sys_design_wiz,
      openai_api_key: api_key
  end
end
