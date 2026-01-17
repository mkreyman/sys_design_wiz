defmodule SysDesignWiz.Telemetry do
  @moduledoc """
  Telemetry event definitions for SysDesignWiz.

  ## Events

  ### LLM Events
  - `[:sys_design_wiz, :llm, :start]` - Emitted when an LLM call begins
  - `[:sys_design_wiz, :llm, :stop]` - Emitted when an LLM call completes successfully
  - `[:sys_design_wiz, :llm, :exception]` - Emitted when an LLM call fails

  ### Launch Library API Events
  - `[:sys_design_wiz, :launch_library, :start]` - Emitted when an API call begins
  - `[:sys_design_wiz, :launch_library, :stop]` - Emitted when an API call completes
  - `[:sys_design_wiz, :launch_library, :exception]` - Emitted when an API call fails

  ### Tool Events
  - `[:sys_design_wiz, :tool, :start]` - Emitted when tool execution begins
  - `[:sys_design_wiz, :tool, :stop]` - Emitted when tool execution completes
  - `[:sys_design_wiz, :tool, :exception]` - Emitted when tool execution fails

  ## Measurements

  All `:stop` and `:exception` events include:
  - `duration` - Time in native units (use `System.convert_time_unit/3` to convert)

  ## Metadata

  - LLM events include: `model`, `message_count`
  - Launch Library events include: `endpoint`, `method`
  - Tool events include: `tool_name`, `action`
  """

  @doc """
  Execute a function and emit telemetry events.

  ## Example

      SysDesignWiz.Telemetry.span([:sys_design_wiz, :llm], %{model: "gpt-4"}, fn ->
        # perform operation
        {:ok, result}
      end)
  """
  def span(event_prefix, metadata, fun) when is_list(event_prefix) and is_function(fun, 0) do
    :telemetry.span(event_prefix, metadata, fn ->
      result = fun.()
      {result, metadata}
    end)
  end

  @doc """
  Emit a custom event.
  """
  def event(name, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(name, measurements, metadata)
  end

  @doc """
  Attach a handler for SysDesignWiz events (useful for testing/debugging).
  """
  def attach_default_logger(handler_id \\ :sys_design_wiz_logger) do
    events = [
      [:sys_design_wiz, :llm, :start],
      [:sys_design_wiz, :llm, :stop],
      [:sys_design_wiz, :llm, :exception],
      [:sys_design_wiz, :launch_library, :start],
      [:sys_design_wiz, :launch_library, :stop],
      [:sys_design_wiz, :launch_library, :exception],
      [:sys_design_wiz, :tool, :start],
      [:sys_design_wiz, :tool, :stop],
      [:sys_design_wiz, :tool, :exception]
    ]

    :telemetry.attach_many(handler_id, events, &log_event/4, nil)
  end

  defp log_event(event, measurements, metadata, _config) do
    require Logger

    duration_ms =
      case measurements[:duration] do
        nil -> nil
        d -> System.convert_time_unit(d, :native, :millisecond)
      end

    Logger.info(
      "[Telemetry] #{inspect(event)} - duration: #{duration_ms}ms, metadata: #{inspect(metadata)}"
    )
  end
end
