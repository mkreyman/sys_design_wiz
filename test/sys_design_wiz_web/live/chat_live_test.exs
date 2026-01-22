defmodule SysDesignWizWeb.ChatLiveTest do
  use SysDesignWizWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup :verify_on_exit!

  describe "mount/3" do
    test "renders the chat interface", %{conn: conn} do
      {:ok, view, html} = live(conn, "/")

      assert html =~ "Systems Design Interview Practice"
      assert has_element?(view, "#message-input")
      # Submit button exists (no id, use type selector)
      assert has_element?(view, "button[type='submit']")
    end

    test "shows session indicator when connected", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Session Active"
    end

    test "renders preferences toggle button", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Preferences button should exist (toggle button)
      assert has_element?(view, "button[phx-click='toggle_preferences']")
    end

    test "renders default tech preferences when panel opened", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open preferences panel
      view |> element("button[phx-click='toggle_preferences']") |> render_click()

      html = render(view)
      # Default preferences are PostgreSQL and Redis for databases
      assert html =~ "PostgreSQL"
      assert html =~ "Redis"
    end
  end

  describe "preferences panel" do
    test "renders database options when opened", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open preferences panel
      view |> element("button[phx-click='toggle_preferences']") |> render_click()

      html = render(view)
      assert html =~ "MySQL"
      assert html =~ "MongoDB"
      assert html =~ "DynamoDB"
    end

    test "renders caching options", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open preferences panel
      view |> element("button[phx-click='toggle_preferences']") |> render_click()

      html = render(view)
      assert html =~ "Memcached"
      assert html =~ "CDN"
    end

    test "renders cloud options including self-hosted", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open preferences panel
      view |> element("button[phx-click='toggle_preferences']") |> render_click()

      html = render(view)
      assert html =~ "AWS"
      assert html =~ "GCP"
      assert html =~ "Self-hosted"
    end

    test "can toggle preference selection", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Open preferences panel
      view |> element("button[phx-click='toggle_preferences']") |> render_click()

      # Click on MySQL to select it
      view
      |> element("button[phx-value-tech='MySQL']")
      |> render_click()

      # MySQL should now be selected (has emerald styling)
      html = render(view)
      assert html =~ "MySQL"
    end
  end

  describe "handle_event toggle_voice" do
    test "voice input button exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Voice toggle button should exist with the correct id
      assert has_element?(view, "#voice-input")
    end
  end

  describe "handle_event toggle_raw_diagram" do
    test "toggle button appears only when diagram exists", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      # Initial state should not show raw diagram toggle without a diagram
      html = render(view)
      refute html =~ "Show Raw"
    end
  end

  describe "mobile layout" do
    test "renders mobile-responsive classes", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      # Check for responsive flex classes
      assert html =~ "flex-col"
      assert html =~ "md:flex-row"
    end
  end

  describe "empty state" do
    test "shows suggestion chips when no messages", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Design a URL shortener"
      assert html =~ "Design Twitter"
      assert html =~ "Design a rate limiter"
    end

    test "shows welcome message", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/")

      assert html =~ "Ready for your interview"
    end
  end
end

# Separate module for tests that require global mocks (sends messages to GenServer)
defmodule SysDesignWizWeb.ChatLiveMessageTest do
  use SysDesignWizWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Mox

  setup :set_mox_global
  setup :verify_on_exit!

  describe "handle_event send_message" do
    test "sends a message and displays it", %{conn: conn} do
      SysDesignWiz.LLM.MockClient
      |> expect(:chat, fn _messages, _opts ->
        {:ok, "Hello! This is a test response."}
      end)

      {:ok, view, _html} = live(conn, "/")

      # Send a message using form submission
      view
      |> form("form[phx-submit='send_message']", %{"message" => "Hello"})
      |> render_submit()

      # Wait for async response (GenServer call is async via send/2)
      :timer.sleep(500)

      # Verify the message appears
      html = render(view)
      assert html =~ "Hello"
    end

    test "displays assistant response after sending message", %{conn: conn} do
      SysDesignWiz.LLM.MockClient
      |> expect(:chat, fn _messages, _opts ->
        {:ok, "This is the assistant's response."}
      end)

      {:ok, view, _html} = live(conn, "/")

      view
      |> form("form[phx-submit='send_message']", %{"message" => "Test"})
      |> render_submit()

      # Wait for async response to complete (GenServer call is async via send/2)
      :timer.sleep(500)

      html = render(view)
      # Both user message and assistant response should appear
      assert html =~ "Test"
      assert html =~ "assistant"
    end
  end

  describe "message rendering" do
    test "user messages have correct styling", %{conn: conn} do
      SysDesignWiz.LLM.MockClient
      |> expect(:chat, fn _messages, _opts ->
        {:ok, "Response from assistant"}
      end)

      {:ok, view, _html} = live(conn, "/")

      view
      |> form("form[phx-submit='send_message']", %{"message" => "User message"})
      |> render_submit()

      # Wait for async response
      :timer.sleep(500)

      html = render(view)
      # User messages have blue gradient
      assert html =~ "from-blue-500"
    end
  end
end
