defmodule SysDesignWiz.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Ensure database directory exists
    ensure_data_directory()

    children = [
      SysDesignWizWeb.Telemetry,
      # SQLite repository for session persistence
      SysDesignWiz.Repo,
      # Background job processing
      {Oban, Application.fetch_env!(:sys_design_wiz, Oban)},
      {DNSCluster, query: Application.get_env(:sys_design_wiz, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: SysDesignWiz.PubSub},
      {Registry, keys: :unique, name: SysDesignWiz.AgentRegistry},
      {DynamicSupervisor, name: SysDesignWiz.AgentSupervisor, strategy: :one_for_one},
      # Circuit breaker for OpenAI API calls
      {SysDesignWiz.LLM.CircuitBreaker, name: SysDesignWiz.LLM.CircuitBreaker},
      SysDesignWizWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SysDesignWiz.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Run migrations after Repo is started
    run_migrations()

    result
  end

  defp ensure_data_directory do
    # Ensure the data directory exists for SQLite database
    db_path = Application.get_env(:sys_design_wiz, SysDesignWiz.Repo)[:database]

    if db_path do
      db_path
      |> Path.dirname()
      |> File.mkdir_p!()
    end
  end

  defp run_migrations do
    # Run Ecto migrations automatically on startup
    # This ensures the database schema is always up-to-date
    Ecto.Migrator.run(
      SysDesignWiz.Repo,
      Application.app_dir(:sys_design_wiz, "priv/repo/migrations"),
      :up,
      all: true
    )
  end

  @impl true
  def config_change(changed, _new, removed) do
    SysDesignWizWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
