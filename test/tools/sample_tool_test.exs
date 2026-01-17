defmodule SysDesignWiz.Tools.SampleToolTest do
  use ExUnit.Case, async: true

  alias SysDesignWiz.Tools.SampleTool
  alias SysDesignWiz.Tools.ToolBehaviour

  describe "name/0" do
    test "returns the tool name" do
      assert SampleTool.name() == "get_current_time"
    end
  end

  describe "description/0" do
    test "returns the tool description" do
      assert is_binary(SampleTool.description())
    end
  end

  describe "parameters/0" do
    test "returns valid JSON Schema" do
      params = SampleTool.parameters()
      assert params["type"] == "object"
      assert is_map(params["properties"])
    end
  end

  describe "to_openai_tool/1" do
    test "returns valid OpenAI function format" do
      definition = ToolBehaviour.to_openai_tool(SampleTool)

      assert definition.type == "function"
      assert definition.function.name == "get_current_time"
      assert is_binary(definition.function.description)
      assert is_map(definition.function.parameters)
    end
  end

  describe "execute/1" do
    test "returns current datetime by default" do
      assert {:ok, result} = SampleTool.execute(%{})
      assert String.contains?(result, "Current time")
      assert String.contains?(result, "UTC")
    end

    test "accepts date format" do
      assert {:ok, result} = SampleTool.execute(%{"format" => "date"})
      assert String.match?(result, ~r/\d{4}-\d{2}-\d{2}/)
    end

    test "accepts time format" do
      assert {:ok, result} = SampleTool.execute(%{"format" => "time"})
      assert String.contains?(result, "UTC")
    end

    test "accepts iso8601 format" do
      assert {:ok, result} = SampleTool.execute(%{"format" => "iso8601"})
      assert String.contains?(result, "T")
    end
  end
end
