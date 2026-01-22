ExUnit.start(capture_log: true)

# Start Claude Code test infrastructure for stubbing
# This starts the ownership server required for ClaudeCode.Test.stub/2
Supervisor.start_link([ClaudeCode.Test], strategy: :one_for_one)

# Start the Ecto sandbox for test isolation
Ecto.Adapters.SQL.Sandbox.mode(SysDesignWiz.Repo, :manual)

# Note: Mox mocks are defined in test/support/mocks.ex to avoid redefinition warnings

# Configure app to use mock clients in tests
Application.put_env(:sys_design_wiz, :llm_client, SysDesignWiz.LLM.MockClient)
Application.put_env(:sys_design_wiz, :spacex_client, SysDesignWiz.SpaceX.MockClient)

Application.put_env(
  :sys_design_wiz,
  :launch_library_client,
  SysDesignWiz.LaunchLibrary.MockClient
)
