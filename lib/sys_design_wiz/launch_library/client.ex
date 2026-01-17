defmodule SysDesignWiz.LaunchLibrary.Client do
  @moduledoc """
  HTTP client for Launch Library 2 API (The Space Devs).

  Provides real-time launch data as the r-spacex API is no longer maintained.
  Uses the development endpoint which has no rate limits for reasonable usage.

  Base URL: https://lldev.thespacedevs.com/2.2.0
  """

  @behaviour SysDesignWiz.LaunchLibrary.ClientBehaviour

  @base_url "https://lldev.thespacedevs.com/2.2.0"
  @timeout 15_000
  @spacex_lsp_id 121

  defp client do
    Req.new(
      base_url: @base_url,
      receive_timeout: @timeout,
      retry: :transient,
      max_retries: 3
    )
  end

  @impl true
  def list_upcoming_launches(limit \\ 5) do
    endpoint = "/launch/upcoming/?lsp__id=#{@spacex_lsp_id}&limit=#{limit}"

    case do_get(endpoint) do
      {:ok, %{"results" => results}} ->
        {:ok, Enum.map(results, &normalize_launch/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list_past_launches(limit \\ 5) do
    endpoint = "/launch/previous/?lsp__id=#{@spacex_lsp_id}&limit=#{limit}"

    case do_get(endpoint) do
      {:ok, %{"results" => results}} ->
        {:ok, Enum.map(results, &normalize_launch/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def get_next_launch do
    case list_upcoming_launches(1) do
      {:ok, [launch | _]} -> {:ok, launch}
      {:ok, []} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def search_launches(opts \\ %{}) do
    query_params = build_search_params(opts)
    endpoint = "/launch/?#{query_params}"

    case do_get(endpoint) do
      {:ok, %{"results" => results}} ->
        {:ok, Enum.map(results, &normalize_launch/1)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def count_launches(opts \\ %{}) do
    # Use limit=1 to minimize data transfer, we only need the count
    query_params = build_search_params(Map.put(opts, :limit, 1))
    endpoint = "/launch/?#{query_params}"

    case do_get(endpoint) do
      {:ok, %{"count" => count}} ->
        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_search_params(opts) do
    params = [{"lsp__id", @spacex_lsp_id}]

    params =
      params
      |> maybe_add_param(opts, :limit, "limit")
      |> maybe_add_param(opts, :name, "search")
      |> maybe_add_param(opts, :rocket, "rocket__configuration__name__icontains")
      |> maybe_add_param(opts, :location, "pad__location__name__icontains")
      |> maybe_add_year_params(opts)
      |> maybe_add_success_params(opts)

    URI.encode_query(params)
  end

  defp maybe_add_param(params, opts, key, param_name) do
    case Map.get(opts, key) do
      nil -> params
      value -> [{param_name, value} | params]
    end
  end

  defp maybe_add_year_params(params, %{year: year}) when is_integer(year) do
    start_date = "#{year}-01-01"
    end_date = "#{year + 1}-01-01"
    [{"net__gte", start_date}, {"net__lt", end_date} | params]
  end

  defp maybe_add_year_params(params, _), do: params

  # Launch Library 2 status IDs: 3 = Success, 4 = Failure
  defp maybe_add_success_params(params, %{success: true}),
    do: [{"status__id", 3} | params]

  defp maybe_add_success_params(params, %{success: false}),
    do: [{"status__id", 4} | params]

  defp maybe_add_success_params(params, _), do: params

  defp do_get(endpoint) do
    client()
    |> Req.get(url: endpoint)
    |> handle_response()
  end

  defp handle_response({:ok, %{status: 200, body: body}}), do: {:ok, body}
  defp handle_response({:ok, %{status: 404}}), do: {:error, :not_found}
  defp handle_response({:ok, %{status: 429}}), do: {:error, :rate_limited}
  defp handle_response({:ok, %{status: status}}), do: {:error, {:http_error, status}}
  defp handle_response({:error, reason}), do: {:error, reason}

  # Normalize Launch Library 2 response to match our expected format
  defp normalize_launch(launch) do
    %{
      "id" => launch["id"],
      "name" => extract_mission_name(launch["name"]),
      "full_name" => launch["name"],
      "flight_number" => nil,
      "date_utc" => launch["net"],
      "upcoming" => launch["status"]["id"] in [1, 2, 3, 8],
      "success" => launch["status"]["id"] == 3,
      "status_name" => launch["status"]["name"],
      "details" => get_in(launch, ["mission", "description"]),
      "rocket" => get_in(launch, ["rocket", "configuration", "name"]),
      "launchpad" => get_in(launch, ["pad", "name"]),
      "location" => get_in(launch, ["pad", "location", "name"]),
      "links" => %{
        "webcast" => find_webcast(launch["vidURLs"])
      }
    }
  end

  # Extract mission name from "Falcon 9 Block 5 | Starlink Group 6-98" format
  defp extract_mission_name(full_name) when is_binary(full_name) do
    case String.split(full_name, " | ", parts: 2) do
      [_, mission] -> mission
      [name] -> name
    end
  end

  defp extract_mission_name(_), do: "Unknown Mission"

  defp find_webcast(nil), do: nil
  defp find_webcast([]), do: nil

  defp find_webcast(urls) when is_list(urls) do
    urls
    |> Enum.find(fn url -> String.contains?(url["url"] || "", "youtube") end)
    |> case do
      %{"url" => url} -> url
      nil -> List.first(urls)["url"]
    end
  end
end
