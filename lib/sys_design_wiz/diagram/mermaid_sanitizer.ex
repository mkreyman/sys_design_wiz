defmodule SysDesignWiz.Diagram.MermaidSanitizer do
  @moduledoc """
  Fixes common Mermaid syntax errors from LLM-generated diagrams.

  LLMs often produce slightly malformed Mermaid code. This module
  attempts to fix common issues to improve rendering success rate.
  """

  @doc """
  Sanitizes Mermaid diagram code by fixing common issues.

  Applies these fixes in order:
  1. Normalize whitespace
  2. Fix special characters in labels
  3. Add missing diagram direction
  4. Balance unclosed subgraphs
  5. Fix common typos

  ## Examples

      iex> MermaidSanitizer.sanitize("flowcahrt TB\\n  A --> B")
      "flowchart TB\\n  A --> B"

      iex> MermaidSanitizer.sanitize("graph\\n  A --> B")
      "graph TD\\n  A --> B"
  """
  @spec sanitize(String.t()) :: String.t()
  def sanitize(code) when is_binary(code) do
    code
    |> normalize_whitespace()
    |> fix_typos()
    |> add_missing_direction()
    |> fix_special_characters()
    |> balance_subgraphs()
    |> String.trim()
  end

  def sanitize(code), do: code

  @doc """
  Validates that Mermaid code has basic structural requirements.

  Returns `{:ok, code}` if valid, or `{:error, reason}` if invalid.
  """
  @spec validate(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def validate(code) when is_binary(code) do
    code
    |> String.trim()
    |> do_validate(code)
  end

  def validate(_), do: {:error, "Invalid input"}

  defp do_validate("", _original), do: {:error, "Empty diagram code"}

  defp do_validate(_trimmed, original) do
    if has_diagram_type?(original) do
      {:ok, original}
    else
      {:error, "Missing diagram type declaration (flowchart, graph, sequence, etc.)"}
    end
  end

  # Private functions

  defp normalize_whitespace(code) do
    code
    |> String.replace(~r/\r\n/, "\n")
    |> String.replace(~r/\t/, "    ")
  end

  defp fix_typos(code) do
    code
    |> String.replace(~r/flowcahrt/i, "flowchart")
    |> String.replace(~r/seqeunce/i, "sequence")
    |> String.replace(~r/digram/i, "diagram")
    |> String.replace(~r/subgrah\b/i, "subgraph")
  end

  defp add_missing_direction(code) do
    # If 'graph' is used without direction, add TD (top-down)
    if Regex.match?(~r/^graph\s*$/m, code) do
      String.replace(code, ~r/^graph\s*$/m, "graph TD")
    else
      code
    end
  end

  defp fix_special_characters(code) do
    # Fix apostrophes in labels that might break parsing
    # "User's Data" -> "Users Data"
    code
    |> String.replace(~r/(\[[^\]]*)'([^\]]*\])/, "\\1\\2")
    |> String.replace(~r/(\([^\)]*)'([^\)]*\))/, "\\1\\2")
    |> String.replace(~r/(\{[^\}]*)'([^\}]*\})/, "\\1\\2")
  end

  defp balance_subgraphs(code) do
    open_count = count_matches(code, ~r/\bsubgraph\b/i)
    end_count = count_matches(code, ~r/\bend\b/i)

    if open_count > end_count do
      missing = open_count - end_count
      code <> String.duplicate("\nend", missing)
    else
      code
    end
  end

  defp has_diagram_type?(code) do
    Regex.match?(
      ~r/^\s*(flowchart|graph|sequenceDiagram|classDiagram|stateDiagram|erDiagram|gantt|pie|journey)/im,
      code
    )
  end

  defp count_matches(string, regex) do
    regex
    |> Regex.scan(string)
    |> length()
  end
end
