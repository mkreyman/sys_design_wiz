defmodule SysDesignWiz.TestMocks do
  @moduledoc """
  Mox mock definitions for testing external dependencies.

  This module is automatically compiled by mix test and defines all mocks
  in a single place to avoid redefinition warnings.
  """

  # LLM Client mock
  Mox.defmock(SysDesignWiz.LLM.MockClient, for: SysDesignWiz.LLM.ClientBehaviour)

  # SpaceX API Client mock
  Mox.defmock(SysDesignWiz.SpaceX.MockClient, for: SysDesignWiz.SpaceX.ClientBehaviour)

  # Launch Library API Client mock
  Mox.defmock(SysDesignWiz.LaunchLibrary.MockClient,
    for: SysDesignWiz.LaunchLibrary.ClientBehaviour
  )
end
