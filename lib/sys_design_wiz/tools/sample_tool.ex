defmodule SysDesignWiz.Tools.SampleTool do
  @moduledoc """
  A sample tool implementation demonstrating the ToolBehaviour pattern.

  This example provides current time - replace with your domain-specific logic.
  """

  @behaviour SysDesignWiz.Tools.ToolBehaviour

  @impl true
  def name, do: "get_current_time"

  @impl true
  def description do
    "Get the current date and time in various formats"
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "format" => %{
          "type" => "string",
          "enum" => ["datetime", "date", "time", "iso8601"],
          "description" => "Output format. Defaults to 'datetime'."
        }
      },
      "required" => []
    }
  end

  @impl true
  def execute(args) do
    format = Map.get(args, "format", "datetime")
    now = DateTime.utc_now()

    result =
      case format do
        "date" -> Calendar.strftime(now, "%Y-%m-%d")
        "time" -> Calendar.strftime(now, "%H:%M:%S UTC")
        "iso8601" -> DateTime.to_iso8601(now)
        _ -> Calendar.strftime(now, "%Y-%m-%d %H:%M:%S UTC")
      end

    {:ok, "Current time: #{result}"}
  end
end
