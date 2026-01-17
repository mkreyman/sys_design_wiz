defmodule SysDesignWiz.Constants.Roles do
  @moduledoc """
  Message role constants for LLM conversations.

  Centralizes role strings to eliminate magic strings and ensure consistency
  across the application.

  ## Usage

      alias SysDesignWiz.Constants.Roles

      # Using constants
      message = %{role: Roles.user(), content: "Hello"}

      # Pattern matching
      case message.role do
        Roles.user() -> handle_user_message(message)
        Roles.assistant() -> handle_assistant_message(message)
        Roles.system() -> handle_system_message(message)
        Roles.tool() -> handle_tool_message(message)
      end
  """

  @user "user"
  @assistant "assistant"
  @system "system"
  @tool "tool"

  @doc "User role for messages sent by the user"
  @spec user() :: String.t()
  def user, do: @user

  @doc "Assistant role for messages from the LLM"
  @spec assistant() :: String.t()
  def assistant, do: @assistant

  @doc "System role for system prompts and instructions"
  @spec system() :: String.t()
  def system, do: @system

  @doc "Tool role for tool execution results"
  @spec tool() :: String.t()
  def tool, do: @tool

  @doc "List of all valid conversation roles"
  @spec all() :: [String.t()]
  def all, do: [@user, @assistant, @system, @tool]

  @doc "Check if a role is valid"
  @spec valid?(String.t()) :: boolean()
  def valid?(role), do: role in all()

  @doc "Check if role represents human input"
  @spec human?(String.t()) :: boolean()
  def human?(role), do: role == @user

  @doc "Check if role represents AI output"
  @spec ai?(String.t()) :: boolean()
  def ai?(role), do: role == @assistant
end
