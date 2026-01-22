defmodule SysDesignWizWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      # The default endpoint for testing
      @endpoint SysDesignWizWeb.Endpoint

      use SysDesignWizWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import SysDesignWizWeb.ConnCase
    end
  end

  setup tags do
    # Checkout the Ecto sandbox for database access
    :ok = Sandbox.checkout(SysDesignWiz.Repo)

    unless tags[:async] do
      Sandbox.mode(SysDesignWiz.Repo, {:shared, self()})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
