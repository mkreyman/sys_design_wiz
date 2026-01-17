defmodule SysDesignWiz.Context.ContextTrimmer do
  @moduledoc """
  Centralized context trimming logic for conversation management.

  Provides consistent message trimming across the application to prevent
  unbounded context growth while preserving important conversation history.

  ## Strategies
  - `:tail` - Keep the most recent N messages (default)
  - `:summary` - Future: Summarize older messages before trimming

  ## Configuration
  Configure via application environment:

      config :sys_design_wiz, SysDesignWiz.Context.ContextTrimmer,
        max_messages: 20,
        preserve_system_prompt: true
  """

  @default_max_messages 20

  @type message :: %{
          required(:role) => String.t(),
          required(:content) => String.t(),
          optional(:timestamp) => DateTime.t()
        }
  @type options :: [max_messages: pos_integer(), preserve_system_prompt: boolean()]

  @doc """
  Trim messages to stay within configured limits.

  ## Options
  - `:max_messages` - Maximum messages to retain (default: #{@default_max_messages})
  - `:preserve_system_prompt` - Keep system message at position 0 (default: true)

  ## Examples

      iex> messages = [%{role: "system", content: "..."}, %{role: "user", content: "hi"}]
      iex> ContextTrimmer.trim(messages, max_messages: 10)
      [%{role: "system", content: "..."}, %{role: "user", content: "hi"}]
  """
  @spec trim([message()], options()) :: [message()]
  def trim(messages, opts \\ []) do
    max = Keyword.get(opts, :max_messages, max_messages())
    preserve_system = Keyword.get(opts, :preserve_system_prompt, true)

    cond do
      length(messages) <= max ->
        messages

      preserve_system and match?([%{role: "system"} | _], messages) ->
        trim_with_system_prompt(messages, max)

      true ->
        Enum.take(messages, -max)
    end
  end

  @doc """
  Trim a list of messages without a system prompt.

  Keeps the most recent N messages.
  """
  @spec trim_history([message()], pos_integer()) :: [message()]
  def trim_history(messages, max_messages \\ max_messages()) do
    if length(messages) > max_messages do
      Enum.take(messages, -max_messages)
    else
      messages
    end
  end

  @doc """
  Check if messages exceed the configured limit.
  """
  @spec needs_trimming?([message()], pos_integer()) :: boolean()
  def needs_trimming?(messages, max_messages \\ max_messages()) do
    length(messages) > max_messages
  end

  @doc """
  Get the configured maximum messages.
  """
  @spec max_messages() :: pos_integer()
  def max_messages do
    config()[:max_messages] || @default_max_messages
  end

  # Private functions

  defp trim_with_system_prompt([system | rest], max) do
    # Keep system message plus the last (max - 1) messages
    trimmed_rest = Enum.take(rest, -(max - 1))
    [system | trimmed_rest]
  end

  defp config do
    Application.get_env(:sys_design_wiz, __MODULE__, [])
  end
end
