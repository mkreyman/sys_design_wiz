defmodule SysDesignWiz.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SysDesignWizWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:sys_design_wiz, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SysDesignWiz.PubSub},
      {Registry, keys: :unique, name: SysDesignWiz.AgentRegistry},
      {DynamicSupervisor, name: SysDesignWiz.AgentSupervisor, strategy: :one_for_one},
      # Circuit breaker for OpenAI API calls
      {SysDesignWiz.LLM.CircuitBreaker, name: SysDesignWiz.LLM.CircuitBreaker},
      SysDesignWizWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SysDesignWiz.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SysDesignWizWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
