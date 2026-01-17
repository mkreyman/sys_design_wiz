defmodule SysDesignWiz.LaunchLibrary.ClientBehaviour do
  @moduledoc """
  Behaviour for Launch Library 2 API client.

  Defines callbacks for fetching real-time launch data from
  The Space Devs Launch Library 2 API.
  """

  @type search_opts :: %{
          optional(:year) => pos_integer(),
          optional(:success) => boolean(),
          optional(:name) => String.t(),
          optional(:rocket) => String.t(),
          optional(:location) => String.t(),
          optional(:limit) => pos_integer()
        }

  @doc "Get upcoming SpaceX launches"
  @callback list_upcoming_launches(limit :: pos_integer()) ::
              {:ok, list(map())} | {:error, term()}

  @doc "Get past SpaceX launches"
  @callback list_past_launches(limit :: pos_integer()) ::
              {:ok, list(map())} | {:error, term()}

  @doc "Get next upcoming SpaceX launch"
  @callback get_next_launch() :: {:ok, map()} | {:error, term()}

  @doc "Search launches with filters"
  @callback search_launches(opts :: search_opts()) ::
              {:ok, list(map())} | {:error, term()}

  @doc "Count launches matching filters"
  @callback count_launches(opts :: search_opts()) ::
              {:ok, non_neg_integer()} | {:error, term()}
end
