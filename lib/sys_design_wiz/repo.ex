defmodule SysDesignWiz.Repo do
  @moduledoc """
  SQLite repository for session persistence.

  Uses SQLite for lightweight, file-based storage that survives
  application restarts and crashes.
  """

  use Ecto.Repo,
    otp_app: :sys_design_wiz,
    adapter: Ecto.Adapters.SQLite3
end
