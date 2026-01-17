defmodule SysDesignWizWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.live_view.mount.stop.duration",
        unit: {:native, :millisecond},
        tags: [:view]
      ),
      summary("phoenix.live_view.handle_event.stop.duration",
        unit: {:native, :millisecond},
        tags: [:view, :event]
      )
    ]
  end

  defp periodic_measurements do
    [
      {__MODULE__, :agent_count, []}
    ]
  end

  def agent_count do
    count =
      case Process.whereis(SysDesignWiz.AgentSupervisor) do
        nil ->
          0

        _pid ->
          DynamicSupervisor.count_children(SysDesignWiz.AgentSupervisor)
          |> Map.get(:active, 0)
      end

    :telemetry.execute([:sys_design_wiz, :agents], %{count: count}, %{})
  end
end
