defmodule SysDesignWiz.Workers.SessionCleanupWorker do
  @moduledoc """
  Oban worker that cleans up stale sessions.

  Runs daily (configured in config.exs) to delete sessions that haven't been
  accessed in the last 24 hours. This prevents unbounded database growth.

  The worker also runs VACUUM to reclaim disk space after deletions.
  """

  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  import Ecto.Query

  alias SysDesignWiz.Context.Session
  alias SysDesignWiz.Repo

  @stale_threshold_hours 24

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Logger.info("Starting session cleanup job")

    cutoff = DateTime.add(DateTime.utc_now(), -@stale_threshold_hours, :hour)

    {deleted_count, _} =
      Session
      |> where([s], s.updated_at < ^cutoff)
      |> Repo.delete_all()

    Logger.info("Session cleanup completed",
      deleted_sessions: deleted_count,
      cutoff_time: DateTime.to_iso8601(cutoff)
    )

    # Reclaim disk space
    vacuum_database()

    :ok
  end

  @doc """
  Manually trigger session cleanup.

  Useful for testing or immediate cleanup needs.
  """
  @spec cleanup_now() :: {:ok, Oban.Job.t()} | {:error, term()}
  def cleanup_now do
    %{}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Delete sessions older than the specified number of hours.

  Returns the count of deleted sessions.
  """
  @spec delete_stale_sessions(non_neg_integer()) :: non_neg_integer()
  def delete_stale_sessions(hours \\ @stale_threshold_hours) do
    cutoff = DateTime.add(DateTime.utc_now(), -hours, :hour)

    {deleted_count, _} =
      Session
      |> where([s], s.updated_at < ^cutoff)
      |> Repo.delete_all()

    deleted_count
  end

  defp vacuum_database do
    # SQLite VACUUM to reclaim disk space
    Repo.query!("VACUUM")
    Logger.debug("Database vacuumed successfully")
  rescue
    error ->
      Logger.warning("Failed to vacuum database: #{inspect(error)}")
  end
end
