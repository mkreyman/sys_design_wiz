defmodule SysDesignWizWeb.Gettext do
  @moduledoc """
  A module providing internationalization with a gettext-based API.
  """
  use Gettext.Backend, otp_app: :sys_design_wiz
end
