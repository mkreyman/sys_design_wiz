defmodule SysDesignWiz.Tools.SpaceXTool do
  @moduledoc """
  Tool for querying SpaceX launch and rocket data.

  Provides the ConversationAgent with access to:
  - Upcoming and past launches (real-time data from Launch Library 2)
  - Rocket specifications (from SpaceX API)
  - Launch search by various criteria
  - Launch count statistics

  ## Data Sources

  - **Launch data**: Launch Library 2 API (lldev.thespacedevs.com) - Real-time SpaceX launches
  - **Rocket data**: SpaceX API (api.spacexdata.com) - Rocket specifications
  """

  @behaviour SysDesignWiz.Tools.ToolBehaviour

  # Configurable clients for testing
  defp spacex_client do
    Application.get_env(:sys_design_wiz, :spacex_client, SysDesignWiz.SpaceX.Client)
  end

  defp launch_library_client do
    Application.get_env(
      :sys_design_wiz,
      :launch_library_client,
      SysDesignWiz.LaunchLibrary.Client
    )
  end

  @impl true
  def name, do: "spacex_data"

  @impl true
  def description do
    "Query SpaceX launch and rocket data. Get information about upcoming launches, " <>
      "past missions, rocket specifications, and search launch history."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "action" => %{
          "type" => "string",
          "enum" => [
            "upcoming_launches",
            "latest_launch",
            "next_launch",
            "past_launches",
            "search_launches",
            "launch_count",
            "list_rockets",
            "rocket_info"
          ],
          "description" => "The action to perform"
        },
        "limit" => %{
          "type" => "integer",
          "description" => "Maximum number of results to return (default: 5)"
        },
        "rocket_id" => %{
          "type" => "string",
          "description" => "Rocket ID for filtering. Common IDs: falcon9, falconheavy, starship"
        },
        "rocket_name" => %{
          "type" => "string",
          "description" => "Rocket name to look up (e.g., 'Falcon 9', 'Falcon Heavy', 'Starship')"
        },
        "year" => %{
          "type" => "integer",
          "description" => "Filter launches by year"
        },
        "success" => %{
          "type" => "boolean",
          "description" => "Filter by launch success status"
        },
        "name" => %{
          "type" => "string",
          "description" => "Search for launches by mission name (e.g., 'Starlink', 'CRS-21')"
        },
        "launchpad" => %{
          "type" => "string",
          "description" =>
            "Filter by launch site (e.g., 'Vandenberg', 'Kennedy', 'Cape Canaveral')"
        }
      },
      "required" => ["action"]
    }
  end

  @impl true
  def execute(args) do
    action = Map.get(args, "action")
    metadata = %{tool_name: name(), action: action}

    SysDesignWiz.Telemetry.span([:sys_design_wiz, :tool], metadata, fn ->
      dispatch_action(action, args)
    end)
  end

  defp dispatch_action("upcoming_launches", args),
    do: get_upcoming_launches(Map.get(args, "limit", 5))

  defp dispatch_action("latest_launch", _args), do: get_latest_launch()
  defp dispatch_action("next_launch", _args), do: get_next_launch()
  defp dispatch_action("past_launches", args), do: get_past_launches(Map.get(args, "limit", 5))
  defp dispatch_action("search_launches", args), do: search_launches(args)
  defp dispatch_action("launch_count", args), do: count_launches(args)
  defp dispatch_action("list_rockets", _args), do: list_rockets()
  defp dispatch_action("rocket_info", args), do: get_rocket_info(args)
  defp dispatch_action(action, _args), do: {:error, "Unknown action: #{action}"}

  # ============================================
  # Action Implementations
  # ============================================

  # Uses Launch Library 2 API for real-time data
  defp get_upcoming_launches(limit) do
    case launch_library_client().list_upcoming_launches(limit) do
      {:ok, launches} ->
        result =
          launches
          |> Enum.map(&format_ll2_launch/1)
          |> Enum.join("\n\n")

        {:ok, "## Upcoming SpaceX Launches\n\n#{result}"}

      {:error, reason} ->
        {:error, "Failed to fetch upcoming launches: #{inspect(reason)}"}
    end
  end

  # Uses Launch Library 2 API for real-time data
  defp get_latest_launch do
    case launch_library_client().list_past_launches(1) do
      {:ok, [launch | _]} ->
        {:ok, "## Latest SpaceX Launch\n\n#{format_ll2_launch_detailed(launch)}"}

      {:ok, []} ->
        {:error, "No recent launches found"}

      {:error, reason} ->
        {:error, "Failed to fetch latest launch: #{inspect(reason)}"}
    end
  end

  # Uses Launch Library 2 API for real-time data
  defp get_next_launch do
    case launch_library_client().get_next_launch() do
      {:ok, launch} ->
        {:ok, "## Next Scheduled Launch\n\n#{format_ll2_launch_detailed(launch)}"}

      {:error, reason} ->
        {:error, "Failed to fetch next launch: #{inspect(reason)}"}
    end
  end

  # Uses Launch Library 2 API for real-time data
  defp get_past_launches(limit) do
    case launch_library_client().list_past_launches(limit) do
      {:ok, launches} ->
        result =
          launches
          |> Enum.map(&format_ll2_launch/1)
          |> Enum.join("\n\n")

        {:ok, "## Recent SpaceX Launches\n\n#{result}"}

      {:error, reason} ->
        {:error, "Failed to fetch past launches: #{inspect(reason)}"}
    end
  end

  # Uses Launch Library 2 API for real-time data
  defp search_launches(args) do
    opts = build_ll2_search_opts(args)

    case launch_library_client().search_launches(opts) do
      {:ok, []} ->
        {:ok, "No launches found matching your criteria."}

      {:ok, launches} ->
        result =
          launches
          |> Enum.map(&format_ll2_launch/1)
          |> Enum.join("\n\n")

        {:ok, "## Launch Search Results\n\n#{result}"}

      {:error, reason} ->
        {:error, "Failed to search launches: #{inspect(reason)}"}
    end
  end

  # Uses Launch Library 2 API for real-time data
  defp count_launches(args) do
    opts = build_ll2_search_opts(args)

    case launch_library_client().count_launches(opts) do
      {:ok, count} ->
        {:ok, format_count_result(count, args)}

      {:error, reason} ->
        {:error, "Failed to count launches: #{inspect(reason)}"}
    end
  end

  defp build_ll2_search_opts(args) do
    %{}
    |> maybe_put_opt(args, "limit", :limit)
    |> maybe_put_opt(args, "year", :year)
    |> maybe_put_opt(args, "success", :success)
    |> maybe_put_opt(args, "name", :name)
    |> maybe_put_rocket_opt(args)
    |> maybe_put_location_opt(args)
  end

  defp maybe_put_opt(opts, args, arg_key, opt_key) do
    case Map.get(args, arg_key) do
      nil -> opts
      value -> Map.put(opts, opt_key, value)
    end
  end

  defp maybe_put_rocket_opt(opts, %{"rocket_name" => name}) when is_binary(name),
    do: Map.put(opts, :rocket, name)

  defp maybe_put_rocket_opt(opts, _), do: opts

  defp maybe_put_location_opt(opts, %{"launchpad" => location}) when is_binary(location),
    do: Map.put(opts, :location, location)

  defp maybe_put_location_opt(opts, _), do: opts

  defp format_count_result(count, args) do
    filters = describe_filters(args)

    """
    ## Launch Count Statistics

    **Total Launches#{filters}:** #{format_number(count)}
    """
  end

  defp describe_filters(args) do
    filters =
      []
      |> maybe_add_filter_description(args, "year", fn y -> "in #{y}" end)
      |> maybe_add_filter_description(args, "success", fn
        true -> "successful"
        false -> "failed"
      end)
      |> maybe_add_filter_description(args, "name", fn n -> "matching '#{n}'" end)
      |> maybe_add_filter_description(args, "rocket_name", fn r -> "using #{r}" end)
      |> maybe_add_filter_description(args, "rocket_id", fn r -> "with rocket #{r}" end)

    case filters do
      [] -> ""
      _ -> " (#{Enum.join(filters, ", ")})"
    end
  end

  defp maybe_add_filter_description(acc, args, key, format_fn) do
    case Map.get(args, key) do
      nil -> acc
      value -> [format_fn.(value) | acc]
    end
  end

  defp list_rockets do
    case spacex_client().list_rockets() do
      {:ok, rockets} ->
        result =
          rockets
          |> Enum.filter(& &1["active"])
          |> Enum.map(&format_rocket_summary/1)
          |> Enum.join("\n\n")

        {:ok, "## SpaceX Active Rockets\n\n#{result}"}

      {:error, reason} ->
        {:error, "Failed to fetch rockets: #{inspect(reason)}"}
    end
  end

  defp get_rocket_info(args) do
    rocket_name = Map.get(args, "rocket_name")
    rocket_id = Map.get(args, "rocket_id") || find_rocket_id(rocket_name)

    if rocket_id do
      case spacex_client().get_rocket(rocket_id) do
        {:ok, rocket} ->
          {:ok, "## Rocket: #{rocket["name"]}\n\n#{format_rocket_detailed(rocket)}"}

        {:error, reason} ->
          {:error, "Failed to fetch rocket info: #{inspect(reason)}"}
      end
    else
      {:error, "Please specify a rocket_id or rocket_name"}
    end
  end

  # ============================================
  # Formatting Helpers (Rocket data from SpaceX API)
  # ============================================

  defp format_rocket_summary(rocket) do
    """
    **#{rocket["name"]}**
    - Type: #{rocket["type"]}
    - Success Rate: #{rocket["success_rate_pct"]}%
    - Cost per Launch: $#{format_number(rocket["cost_per_launch"])}
    """
  end

  defp format_rocket_detailed(rocket) do
    """
    - Type: #{rocket["type"]}
    - Active: #{rocket["active"]}
    - Stages: #{rocket["stages"]}
    - Height: #{get_in(rocket, ["height", "meters"])} meters
    - Mass: #{format_number(get_in(rocket, ["mass", "kg"]))} kg
    - Success Rate: #{rocket["success_rate_pct"]}%
    - Cost per Launch: $#{format_number(rocket["cost_per_launch"])}
    - First Flight: #{rocket["first_flight"]}
    - Description: #{rocket["description"]}
    """
  end

  defp format_date(nil), do: "TBD"

  defp format_date(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%B %d, %Y at %H:%M UTC")
      _ -> date_string
    end
  end

  defp format_number(num), do: SysDesignWiz.Formatting.number_to_delimited(num)

  # ============================================
  # Launch Library 2 Formatters
  # ============================================

  defp format_ll2_launch(launch) do
    date = format_date(launch["date_utc"])
    status = launch["status_name"] || "Unknown"

    """
    **#{launch["name"]}**
    - Date: #{date}
    - Status: #{status}
    - Rocket: #{launch["rocket"]}
    - Location: #{launch["location"]}
    """
  end

  defp format_ll2_launch_detailed(launch) do
    date = format_date(launch["date_utc"])
    status = launch["status_name"] || "Unknown"
    details = launch["details"] || "No mission details available"

    webcast =
      case get_in(launch, ["links", "webcast"]) do
        nil -> ""
        url -> "- Webcast: #{url}\n"
      end

    """
    **#{launch["name"]}**
    - Date: #{date}
    - Status: #{status}
    - Rocket: #{launch["rocket"]}
    - Launch Site: #{launch["launchpad"]}
    - Location: #{launch["location"]}
    - Mission: #{details}
    #{webcast}
    """
  end

  # ============================================
  # Rocket ID Lookup (for SpaceX API rocket queries)
  # ============================================

  # Default rocket IDs - configurable via :sys_design_wiz, :rocket_ids
  # These IDs are from the SpaceX API and may change if the API is updated.
  @default_rocket_ids %{
    "falcon 1" => "5e9d0d95eda69955f709d1eb",
    "falcon1" => "5e9d0d95eda69955f709d1eb",
    "falcon 9" => "5e9d0d95eda69973a809d1ec",
    "falcon9" => "5e9d0d95eda69973a809d1ec",
    "falcon heavy" => "5e9d0d95eda69974db09d1ed",
    "falconheavy" => "5e9d0d95eda69974db09d1ed",
    "starship" => "5e9d0d96eda699382d09d1ee"
  }

  defp rocket_ids do
    Application.get_env(:sys_design_wiz, :rocket_ids, @default_rocket_ids)
  end

  defp find_rocket_id(nil), do: nil

  defp find_rocket_id(name) when is_binary(name) do
    Map.get(rocket_ids(), String.downcase(name))
  end
end
