defmodule SysDesignWiz.SpaceX.ClientBehaviour do
  @moduledoc """
  Behaviour for SpaceX API client.

  The SpaceX API provides rocket specifications and static reference data.
  For real-time launch data, use `SysDesignWiz.LaunchLibrary.ClientBehaviour`.

  Implementations must provide all callback functions.
  Used for dependency injection in tests via Mox.

  All functions return `{:ok, data}` on success or `{:error, reason}` on failure.
  """

  @type rocket :: map()
  @type error :: {:error, term()}

  @doc "List all rockets"
  @callback list_rockets() :: {:ok, [rocket()]} | error()

  @doc "Get rocket by ID"
  @callback get_rocket(id :: String.t()) :: {:ok, rocket()} | error()
end
