defmodule SysDesignWiz.Fixtures do
  @moduledoc """
  Test fixtures and helpers.

  Use `build/2` for data fixtures (maps), `mock_*` functions for Mox expectations.
  """

  import Mox

  alias SysDesignWiz.LLM.MockClient

  # ============================================
  # SpaceX Data Fixtures
  # ============================================

  @doc """
  Build a SpaceX launch fixture.

  ## Examples

      build(:launch, %{"name" => "Starlink Mission"})
      build(:upcoming_launch, %{})
  """
  def build(:launch, attrs) do
    defaults = %{
      "id" => "launch_#{System.unique_integer([:positive])}",
      "name" => "Test Launch #{System.unique_integer([:positive])}",
      "flight_number" => :rand.uniform(500),
      "date_utc" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "date_precision" => "hour",
      "upcoming" => false,
      "success" => true,
      "details" => "Test launch details",
      "rocket" => "5e9d0d95eda69973a809d1ec",
      "launchpad" => "5e9e4502f509094188566f88",
      "links" => %{
        "webcast" => "https://youtube.com/watch?v=test",
        "patch" => %{"small" => nil, "large" => nil}
      },
      "cores" => [%{"core" => "core123", "flight" => 1, "reused" => false}],
      "payloads" => [],
      "crew" => []
    }

    Map.merge(defaults, stringify_keys(attrs))
  end

  def build(:upcoming_launch, attrs) do
    future_date =
      DateTime.utc_now()
      |> DateTime.add(7, :day)
      |> DateTime.to_iso8601()

    build(
      :launch,
      Map.merge(
        %{
          "upcoming" => true,
          "success" => nil,
          "date_utc" => future_date
        },
        attrs
      )
    )
  end

  def build(:rocket, attrs) do
    defaults = %{
      "id" => "rocket_#{System.unique_integer([:positive])}",
      "name" => "Falcon 9",
      "type" => "rocket",
      "active" => true,
      "stages" => 2,
      "boosters" => 0,
      "cost_per_launch" => 50_000_000,
      "success_rate_pct" => 98,
      "first_flight" => "2010-06-04",
      "country" => "United States",
      "company" => "SpaceX",
      "height" => %{"meters" => 70, "feet" => 229.6},
      "diameter" => %{"meters" => 3.7, "feet" => 12},
      "mass" => %{"kg" => 549_054, "lb" => 1_207_920},
      "description" => "Falcon 9 is a two-stage rocket designed and manufactured by SpaceX."
    }

    Map.merge(defaults, stringify_keys(attrs))
  end

  def build(:query_response, opts) do
    docs = Keyword.get(opts, :docs, [])
    total = Keyword.get(opts, :total, length(docs))

    %{
      "docs" => docs,
      "totalDocs" => total,
      "offset" => 0,
      "limit" => 20,
      "totalPages" => max(1, ceil(total / 20)),
      "page" => 1,
      "hasNextPage" => total > 20,
      "hasPrevPage" => false
    }
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp stringify_keys(other), do: other

  @doc """
  Setup mock LLM client to return a specific response.
  """
  def mock_llm_response(response) do
    expect(MockClient, :chat, fn _messages, _opts ->
      {:ok, response}
    end)
  end

  @doc """
  Setup mock LLM client to return multiple responses in sequence.
  """
  def mock_llm_responses(responses) when is_list(responses) do
    for response <- responses do
      expect(MockClient, :chat, fn _messages, _opts ->
        {:ok, response}
      end)
    end
  end

  @doc """
  Setup mock LLM client to return an error.
  """
  def mock_llm_error(error \\ :timeout) do
    expect(MockClient, :chat, fn _messages, _opts ->
      {:error, error}
    end)
  end

  @doc """
  Sample messages for testing.
  """
  def sample_messages do
    [
      %{role: "system", content: "You are a helpful assistant."},
      %{role: "user", content: "Hello!"},
      %{role: "assistant", content: "Hi there! How can I help you today?"}
    ]
  end
end
