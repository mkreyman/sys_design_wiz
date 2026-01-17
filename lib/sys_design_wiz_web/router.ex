defmodule SysDesignWizWeb.Router do
  use SysDesignWizWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {SysDesignWizWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", SysDesignWizWeb do
    pipe_through(:browser)

    live("/", ChatLive, :index)
  end

  if Application.compile_env(:sys_design_wiz, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: SysDesignWizWeb.Telemetry)
    end
  end
end
