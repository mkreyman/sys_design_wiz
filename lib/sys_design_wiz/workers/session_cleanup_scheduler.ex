defmodule SysDesignWiz.Workers.SessionCleanupScheduler do
  @moduledoc """
  GenServer that schedules daily session cleanup.

  Runs cleanup at 3 AM UTC daily to delete sessions that haven't been
  accessed in the last 24 hours. This prevents unbounded database growth.

  Uses a simple timer-based approach instead of Oban for SQLite compatibility.
  """

  use GenServer

  require Logger

  import Ecto.Query

  alias SysDesignWiz.Context.Session
  alias SysDesignWiz.Repo

  @stale_threshold_hours 24
  @check_interval :timer.hours(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Manually trigger session cleanup.
  """
  @spec cleanup_now() :: :ok
  def cleanup_now do
    GenServer.cast(__MODULE__, :cleanup)
  end

  @impl true
  def init(_opts) do
    # Schedule first check
    schedule_check()
    {:ok, %{last_cleanup: nil}}
  end

  @impl true
  def handle_info(:check_cleanup, state) do
    state = maybe_run_cleanup(state)
    schedule_check()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:cleanup, state) do
    run_cleanup()
    {:noreply, %{state | last_cleanup: DateTime.utc_now()}}
  end

  defp schedule_check do
    Process.send_after(self(), :check_cleanup, @check_interval)
  end

  defp maybe_run_cleanup(state) do
    now = DateTime.utc_now()

    if should_run_cleanup?(now, state.last_cleanup) do
      run_cleanup()
      %{state | last_cleanup: now}
    else
      state
    end
  end

  defp should_run_cleanup?(now, last_cleanup) do
    # Run at 3 AM UTC if we haven't run today
    hour = now.hour
    is_cleanup_hour = hour == 3

    has_run_today =
      case last_cleanup do
        nil -> false
        last -> Date.compare(DateTime.to_date(last), DateTime.to_date(now)) == :eq
      end

    is_cleanup_hour and not has_run_today
  end

  defp run_cleanup do
    Logger.info("Starting session cleanup")

    cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold_hours, :hour)

    {deleted_count, _} =
      Session
      |> where([s], s.updated_at < ^cutoff)
      |> Repo.delete_all()

    Logger.info("Session cleanup completed",
      deleted_sessions: deleted_count,
      cutoff_time: DateTime.to_iso8601(cutoff)
    )

    vacuum_database()

    :ok
  rescue
    error ->
      Logger.error("Session cleanup failed: #{inspect(error)}")
      :error
  end

  defp vacuum_database do
    Repo.query!("VACUUM")
    Logger.debug("Database vacuumed successfully")
  rescue
    error ->
      Logger.warning("Failed to vacuum database: #{inspect(error)}")
  end
end
