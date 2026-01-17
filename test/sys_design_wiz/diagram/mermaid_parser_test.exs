defmodule SysDesignWiz.Diagram.MermaidParserTest do
  use ExUnit.Case, async: true

  alias SysDesignWiz.Diagram.MermaidParser

  describe "extract/1" do
    test "extracts mermaid code from fenced block" do
      response = """
      Here's the design:

      ```mermaid
      flowchart TB
        A --> B
      ```

      Pretty cool right?
      """

      assert {:ok, diagram} = MermaidParser.extract(response)
      assert diagram == "flowchart TB\n  A --> B"
    end

    test "returns last diagram when multiple exist" do
      response = """
      First design:
      ```mermaid
      flowchart TB
        A --> B
      ```

      Revised design:
      ```mermaid
      flowchart LR
        X --> Y --> Z
      ```
      """

      assert {:ok, diagram} = MermaidParser.extract(response)
      assert diagram == "flowchart LR\n  X --> Y --> Z"
    end

    test "handles case-insensitive mermaid marker" do
      response = """
      ```MERMAID
      graph TD
        Start --> End
      ```
      """

      assert {:ok, diagram} = MermaidParser.extract(response)
      assert diagram == "graph TD\n  Start --> End"
    end

    test "returns :no_diagram when no mermaid block exists" do
      response = "Just some text without any diagram"
      assert MermaidParser.extract(response) == :no_diagram
    end

    test "returns :no_diagram for other code blocks" do
      response = """
      ```javascript
      const x = 1;
      ```
      """

      assert MermaidParser.extract(response) == :no_diagram
    end

    test "returns :no_diagram for non-binary input" do
      assert MermaidParser.extract(nil) == :no_diagram
      assert MermaidParser.extract(123) == :no_diagram
    end
  end

  describe "has_diagram?/1" do
    test "returns true when mermaid block exists" do
      response = "```mermaid\nflowchart TB\n```"
      assert MermaidParser.has_diagram?(response) == true
    end

    test "returns false when no mermaid block" do
      response = "No diagram here"
      assert MermaidParser.has_diagram?(response) == false
    end

    test "returns false for non-binary input" do
      assert MermaidParser.has_diagram?(nil) == false
    end
  end

  describe "extract_all/1" do
    test "returns all diagrams in order" do
      response = """
      First: ```mermaid
      A
      ```
      Second: ```mermaid
      B
      ```
      """

      assert MermaidParser.extract_all(response) == ["A", "B"]
    end

    test "returns empty list when no diagrams" do
      assert MermaidParser.extract_all("no diagrams") == []
    end

    test "returns empty list for non-binary input" do
      assert MermaidParser.extract_all(nil) == []
    end
  end

  describe "strip_diagrams/1" do
    test "removes mermaid blocks from response" do
      response = """
      Check this:
      ```mermaid
      A-->B
      ```
      Cool right?
      """

      result = MermaidParser.strip_diagrams(response)
      assert result == "Check this:\n\nCool right?"
    end

    test "collapses multiple newlines" do
      response = """
      Before



      ```mermaid
      X
      ```



      After
      """

      result = MermaidParser.strip_diagrams(response)
      refute result =~ "\n\n\n"
    end

    test "returns original for non-binary input" do
      assert MermaidParser.strip_diagrams(nil) == nil
    end
  end
end
