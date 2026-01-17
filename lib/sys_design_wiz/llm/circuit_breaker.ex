defmodule SysDesignWiz.LLM.CircuitBreaker do
  @moduledoc """
  Circuit breaker for external API calls.

  Tracks failures and prevents cascading failures by short-circuiting
  calls when error thresholds are exceeded.

  ## States
  - `:closed` - Normal operation, calls pass through
  - `:open` - Circuit is open, calls fail fast
  - `:half_open` - Testing if service recovered

  ## Configuration
  - `failure_threshold` - Number of failures before opening circuit (default: 5)
  - `reset_timeout_ms` - Time before attempting recovery (default: 30_000)
  - `success_threshold` - Successes needed to close from half-open (default: 2)
  """

  use GenServer

  require Logger

  @default_failure_threshold 5
  @default_reset_timeout_ms 30_000
  @default_success_threshold 2

  # Client API

  @doc """
  Starts the circuit breaker process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Execute a function through the circuit breaker.

  Returns `{:error, :circuit_open}` if the circuit is open.
  """
  @spec call(GenServer.server(), (-> result)) :: result | {:error, :circuit_open}
        when result: any()
  def call(server \\ __MODULE__, fun) when is_function(fun, 0) do
    GenServer.call(server, {:call, fun})
  end

  @doc """
  Get the current state of the circuit breaker.
  """
  @spec state(GenServer.server()) :: :closed | :open | :half_open
  def state(server \\ __MODULE__) do
    GenServer.call(server, :state)
  end

  @doc """
  Get detailed statistics about the circuit breaker.
  """
  @spec stats(GenServer.server()) :: map()
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @doc """
  Reset the circuit breaker to closed state.
  """
  @spec reset(GenServer.server()) :: :ok
  def reset(server \\ __MODULE__) do
    GenServer.call(server, :reset)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    state = %{
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      failure_threshold: Keyword.get(opts, :failure_threshold, @default_failure_threshold),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, @default_reset_timeout_ms),
      success_threshold: Keyword.get(opts, :success_threshold, @default_success_threshold),
      total_calls: 0,
      total_failures: 0,
      total_successes: 0,
      total_rejected: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:call, fun}, _from, %{state: :open} = state) do
    state = maybe_transition_to_half_open(state)

    case state.state do
      :open ->
        Logger.warning("Circuit breaker rejecting call - circuit is open")
        {:reply, {:error, :circuit_open}, %{state | total_rejected: state.total_rejected + 1}}

      :half_open ->
        execute_call(fun, state)
    end
  end

  def handle_call({:call, fun}, _from, state) do
    execute_call(fun, state)
  end

  def handle_call(:state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      failure_threshold: state.failure_threshold,
      reset_timeout_ms: state.reset_timeout_ms,
      total_calls: state.total_calls,
      total_failures: state.total_failures,
      total_successes: state.total_successes,
      total_rejected: state.total_rejected
    }

    {:reply, stats, state}
  end

  def handle_call(:reset, _from, state) do
    Logger.info("Circuit breaker manually reset")

    new_state = %{
      state
      | state: :closed,
        failure_count: 0,
        success_count: 0,
        last_failure_time: nil
    }

    {:reply, :ok, new_state}
  end

  # Private helpers

  defp execute_call(fun, state) do
    state = %{state | total_calls: state.total_calls + 1}

    try do
      result = fun.()
      handle_result(result, state)
    rescue
      e ->
        Logger.error("Circuit breaker caught exception: #{inspect(e)}")
        handle_failure(state)
    end
  end

  defp handle_result({:ok, _} = result, state) do
    {:reply, result, record_success(state)}
  end

  defp handle_result({:error, _} = result, state) do
    {:reply, _, new_state} = handle_failure(state)
    {:reply, result, new_state}
  end

  defp handle_result(result, state) do
    # Non-error/ok tuple results are treated as success
    {:reply, result, record_success(state)}
  end

  defp handle_failure(state) do
    new_state = %{
      state
      | failure_count: state.failure_count + 1,
        success_count: 0,
        last_failure_time: System.monotonic_time(:millisecond),
        total_failures: state.total_failures + 1
    }

    new_state = maybe_open_circuit(new_state)

    {:reply, {:error, :call_failed}, new_state}
  end

  defp record_success(%{state: :half_open} = state) do
    new_count = state.success_count + 1
    new_state = %{state | success_count: new_count, total_successes: state.total_successes + 1}

    if new_count >= state.success_threshold do
      Logger.info("Circuit breaker closing after successful recovery")
      %{new_state | state: :closed, failure_count: 0, success_count: 0}
    else
      new_state
    end
  end

  defp record_success(state) do
    %{state | total_successes: state.total_successes + 1}
  end

  defp maybe_open_circuit(state) do
    if state.failure_count >= state.failure_threshold do
      Logger.warning("Circuit breaker opening after #{state.failure_count} failures")
      %{state | state: :open}
    else
      state
    end
  end

  defp maybe_transition_to_half_open(state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - (state.last_failure_time || 0)

    if elapsed >= state.reset_timeout_ms do
      Logger.info("Circuit breaker transitioning to half-open state")
      %{state | state: :half_open, success_count: 0}
    else
      state
    end
  end
end
