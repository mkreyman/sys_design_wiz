defmodule SysDesignWiz.Diagram.MermaidSanitizerTest do
  use ExUnit.Case, async: true

  alias SysDesignWiz.Diagram.MermaidSanitizer

  describe "sanitize/1" do
    test "fixes flowchart typo" do
      code = "flowcahrt TB\n  A --> B"
      assert MermaidSanitizer.sanitize(code) == "flowchart TB\n  A --> B"
    end

    test "fixes sequence typo" do
      code = "seqeunceDiagram\n  A->>B: Hello"
      assert MermaidSanitizer.sanitize(code) =~ "sequenceDiagram"
    end

    test "fixes subgraph typo" do
      code = "flowchart TB\n  subgrah Services\n    A\n  end"
      assert MermaidSanitizer.sanitize(code) =~ "subgraph Services"
    end

    test "adds missing direction to graph" do
      code = "graph\n  A --> B"
      assert MermaidSanitizer.sanitize(code) == "graph TD\n  A --> B"
    end

    test "does not modify graph with direction" do
      code = "graph LR\n  A --> B"
      assert MermaidSanitizer.sanitize(code) == "graph LR\n  A --> B"
    end

    test "normalizes Windows line endings" do
      code = "flowchart TB\r\n  A --> B"
      result = MermaidSanitizer.sanitize(code)
      refute result =~ "\r"
      assert result =~ "\n"
    end

    test "converts tabs to spaces" do
      code = "flowchart TB\n\tA --> B"
      result = MermaidSanitizer.sanitize(code)
      refute result =~ "\t"
      assert result =~ "    A --> B"
    end

    test "balances unclosed subgraphs" do
      code = "flowchart TB\n  subgraph Services\n    A --> B"
      result = MermaidSanitizer.sanitize(code)
      assert result =~ ~r/end$/
    end

    test "adds multiple ends for multiple unclosed subgraphs" do
      code = "flowchart TB\n  subgraph One\n    subgraph Two\n      A"
      result = MermaidSanitizer.sanitize(code)
      # Should have 2 ends added
      assert String.split(result, "end") |> length() >= 3
    end

    test "does not add extra ends when subgraphs are balanced" do
      code = "flowchart TB\n  subgraph Services\n    A\n  end"
      result = MermaidSanitizer.sanitize(code)
      # Count ends - should still be 1
      end_count = length(Regex.scan(~r/\bend\b/i, result))
      assert end_count == 1
    end

    test "removes apostrophes from labels" do
      code = "flowchart TB\n  A[User's Data] --> B"
      result = MermaidSanitizer.sanitize(code)
      assert result =~ "[Users Data]"
    end

    test "trims whitespace" do
      code = "  flowchart TB\n  A --> B  \n\n"
      result = MermaidSanitizer.sanitize(code)
      assert result == String.trim(result)
    end

    test "returns non-binary input unchanged" do
      assert MermaidSanitizer.sanitize(nil) == nil
      assert MermaidSanitizer.sanitize(123) == 123
    end
  end

  describe "validate/1" do
    test "returns ok for valid flowchart" do
      code = "flowchart TB\n  A --> B"
      assert {:ok, ^code} = MermaidSanitizer.validate(code)
    end

    test "returns ok for valid graph" do
      code = "graph LR\n  A --> B"
      assert {:ok, ^code} = MermaidSanitizer.validate(code)
    end

    test "returns ok for valid sequence diagram" do
      code = "sequenceDiagram\n  A->>B: Hello"
      assert {:ok, ^code} = MermaidSanitizer.validate(code)
    end

    test "returns ok for valid class diagram" do
      code = "classDiagram\n  class Animal"
      assert {:ok, ^code} = MermaidSanitizer.validate(code)
    end

    test "returns ok for valid state diagram" do
      code = "stateDiagram-v2\n  [*] --> Active"
      assert {:ok, ^code} = MermaidSanitizer.validate(code)
    end

    test "returns ok for valid ER diagram" do
      code = "erDiagram\n  USER ||--o{ ORDER : places"
      assert {:ok, ^code} = MermaidSanitizer.validate(code)
    end

    test "returns error for empty code" do
      assert {:error, "Empty diagram code"} = MermaidSanitizer.validate("")
      assert {:error, "Empty diagram code"} = MermaidSanitizer.validate("   ")
    end

    test "returns error for missing diagram type" do
      code = "A --> B\nB --> C"
      assert {:error, message} = MermaidSanitizer.validate(code)
      assert message =~ "Missing diagram type"
    end

    test "returns error for invalid input" do
      assert {:error, "Invalid input"} = MermaidSanitizer.validate(nil)
      assert {:error, "Invalid input"} = MermaidSanitizer.validate(123)
    end
  end
end
