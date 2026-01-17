defmodule SysDesignWiz.SpaceX.Client do
  @moduledoc """
  HTTP client for SpaceX API - Rocket specifications only.

  This client provides rocket data from the SpaceX API.
  For real-time launch data, use `SysDesignWiz.LaunchLibrary.Client`.

  Base URL: https://api.spacexdata.com
  - Rockets: v4 endpoints
  """

  @behaviour SysDesignWiz.SpaceX.ClientBehaviour

  @base_url "https://api.spacexdata.com"
  @timeout 15_000

  defp client do
    Req.new(
      base_url: @base_url,
      receive_timeout: @timeout,
      retry: :transient,
      max_retries: 3
    )
  end

  @impl true
  def list_rockets do
    case Req.get(client(), url: "/v4/rockets") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get_rocket(id) when is_binary(id) do
    case Req.get(client(), url: "/v4/rockets/#{id}") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
