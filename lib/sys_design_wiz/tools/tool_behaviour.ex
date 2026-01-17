defmodule SysDesignWiz.Tools.ToolBehaviour do
  @moduledoc """
  Behaviour defining the interface for agent tools.

  Tools enable the LLM to take actions like searching data, calling APIs,
  or performing calculations. Implement this behaviour to create custom tools.

  ## Example

      defmodule SysDesignWiz.Tools.WeatherTool do
        @behaviour SysDesignWiz.Tools.ToolBehaviour

        @impl true
        def name, do: "get_weather"

        @impl true
        def description, do: "Get current weather for a location"

        @impl true
        def parameters do
          %{
            "type" => "object",
            "properties" => %{
              "location" => %{
                "type" => "string",
                "description" => "City name (e.g., 'San Francisco')"
              }
            },
            "required" => ["location"]
          }
        end

        @impl true
        def execute(%{"location" => location}) do
          # Call weather API...
          {:ok, "72°F and sunny in \#{location}"}
        end
      end
  """

  @type tool_result :: {:ok, String.t()} | {:error, term()}

  @doc """
  Returns the tool name as used in OpenAI function calling.
  """
  @callback name() :: String.t()

  @doc """
  Returns a description of what the tool does.
  """
  @callback description() :: String.t()

  @doc """
  Returns the JSON Schema for the tool's parameters.
  """
  @callback parameters() :: map()

  @doc """
  Executes the tool with the given arguments.

  ## Parameters
  - `args` - Map of arguments matching the parameters schema

  ## Returns
  - `{:ok, result}` - Tool execution succeeded
  - `{:error, reason}` - Tool execution failed
  """
  @callback execute(args :: map()) :: tool_result()

  @doc """
  Converts a tool module to OpenAI function calling format.

  ## Example

      ToolBehaviour.to_openai_tool(SysDesignWiz.Tools.WeatherTool)
      # => %{type: "function", function: %{name: "get_weather", ...}}
  """
  def to_openai_tool(module) do
    %{
      type: "function",
      function: %{
        name: module.name(),
        description: module.description(),
        parameters: module.parameters()
      }
    }
  end
end
