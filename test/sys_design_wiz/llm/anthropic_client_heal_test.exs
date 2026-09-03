defmodule SysDesignWiz.LLM.AnthropicClientHealTest do
  @moduledoc """
  The inline 404 self-heal: when the requested model was retired, the client
  re-resolves the newest model of the same tier (the ModelResolver fallback in
  test) and retries once. Uses the `:http_post` injection to simulate responses.
  """
  use ExUnit.Case, async: false

  alias SysDesignWiz.LLM.AnthropicClient

  setup do
    prev = Application.get_env(:sys_design_wiz, :anthropic_api_key)
    Application.put_env(:sys_design_wiz, :anthropic_api_key, "sk-test")

    on_exit(fn ->
      if prev do
        Application.put_env(:sys_design_wiz, :anthropic_api_key, prev)
      else
        Application.delete_env(:sys_design_wiz, :anthropic_api_key)
      end
    end)

    # Ask the resolver what a cold cache resolves Sonnet to, rather than writing
    # the id out. Fetching is disabled in test, so this is the pinned fallback.
    {:ok, sonnet_fallback: SysDesignWiz.LLM.ModelResolver.latest_model("sk-test", "sonnet")}
  end

  defp not_found_404(model) do
    {:ok,
     %Req.Response{
       status: 404,
       body: %{"error" => %{"type" => "not_found_error", "message" => "model: #{model}"}}
     }}
  end

  defp ok_200 do
    {:ok, %Req.Response{status: 200, body: %{"content" => [%{"type" => "text", "text" => "hi"}]}}}
  end

  test "chat self-heals a 404 not_found by retrying with a re-resolved model",
       %{sonnet_fallback: sonnet_fallback} do
    test_pid = self()
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    post_fun = fn _req, opts ->
      n = Agent.get_and_update(agent, &{&1, &1 + 1})
      send(test_pid, {:posted, n, opts[:json]["model"]})
      if n == 0, do: not_found_404("claude-sonnet-4-20250514"), else: ok_200()
    end

    assert {:ok, "hi"} =
             AnthropicClient.chat([%{role: "user", content: "hi"}],
               model: "claude-sonnet-4-20250514",
               http_post: post_fun
             )

    # First attempt used the retired model; the retry used the resolved newest
    # Sonnet. Asked of the resolver rather than written as a literal: pinning
    # the fallback's spelling here is what made a fallback refresh look like a
    # test failure, which invites "fix" by reverting the refresh.
    assert_received {:posted, 0, "claude-sonnet-4-20250514"}
    assert_received {:posted, 1, ^sonnet_fallback}
  end

  test "chat_with_tools self-heals a 404 not_found", %{sonnet_fallback: sonnet_fallback} do
    test_pid = self()
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    post_fun = fn _req, opts ->
      n = Agent.get_and_update(agent, &{&1, &1 + 1})
      send(test_pid, {:posted, n, opts[:json]["model"]})

      if n == 0,
        do: not_found_404("claude-sonnet-4-20250514"),
        else:
          {:ok,
           %Req.Response{
             status: 200,
             body: %{"content" => [], "stop_reason" => "end_turn"}
           }}
    end

    assert {:ok, _response} =
             AnthropicClient.chat_with_tools([%{role: "user", content: "hi"}], [],
               model: "claude-sonnet-4-20250514",
               http_post: post_fun
             )

    assert_received {:posted, 1, ^sonnet_fallback}
  end

  test "a 404 that is NOT a model not_found is returned as an error (no retry)",
       %{sonnet_fallback: sonnet_fallback} do
    test_pid = self()

    post_fun = fn _req, opts ->
      send(test_pid, {:posted, opts[:json]["model"]})
      {:ok, %Req.Response{status: 404, body: %{"error" => %{"type" => "other_error"}}}}
    end

    assert {:error, _} =
             AnthropicClient.chat([%{role: "user", content: "hi"}],
               model: sonnet_fallback,
               http_post: post_fun
             )

    # Only one attempt — no heal retry for a non-model 404.
    assert_received {:posted, ^sonnet_fallback}
    refute_received {:posted, _other}
  end
end
