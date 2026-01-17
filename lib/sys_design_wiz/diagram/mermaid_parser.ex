defmodule SysDesignWiz.Diagram.MermaidParser do
  @moduledoc """
  Extracts Mermaid diagram code from LLM responses.

  Looks for fenced code blocks with the `mermaid` language identifier
  and returns the diagram code for rendering.
  """

  @mermaid_regex ~r/```mermaid\s*\n([\s\S]*?)\n```/i

  @doc """
  Extracts Mermaid diagram code from a response string.

  Returns `{:ok, diagram_code}` if a diagram is found,
  or `:no_diagram` if no mermaid block exists.

  If multiple diagrams exist, returns the last one (most recent design).

  ## Examples

      iex> MermaidParser.extract("Here's the design:\\n```mermaid\\nflowchart TB\\n  A --> B\\n```")
      {:ok, "flowchart TB\\n  A --> B"}

      iex> MermaidParser.extract("No diagram here")
      :no_diagram
  """
  @spec extract(String.t()) :: {:ok, String.t()} | :no_diagram
  def extract(response) when is_binary(response) do
    case Regex.scan(@mermaid_regex, response) do
      [] ->
        :no_diagram

      matches ->
        # Get the last match (most recent diagram)
        [_, diagram_code] = List.last(matches)
        {:ok, String.trim(diagram_code)}
    end
  end

  def extract(_), do: :no_diagram

  @doc """
  Checks if a response contains a Mermaid diagram.

  ## Examples

      iex> MermaidParser.has_diagram?("```mermaid\\nflowchart TB\\n```")
      true

      iex> MermaidParser.has_diagram?("Just text")
      false
  """
  @spec has_diagram?(String.t()) :: boolean()
  def has_diagram?(response) when is_binary(response) do
    Regex.match?(@mermaid_regex, response)
  end

  def has_diagram?(_), do: false

  @doc """
  Extracts all Mermaid diagrams from a response.

  Returns a list of diagram codes in order of appearance.

  ## Examples

      iex> MermaidParser.extract_all("First: ```mermaid\\nA```\\nSecond: ```mermaid\\nB```")
      ["A", "B"]
  """
  @spec extract_all(String.t()) :: [String.t()]
  def extract_all(response) when is_binary(response) do
    @mermaid_regex
    |> Regex.scan(response)
    |> Enum.map(fn [_, code] -> String.trim(code) end)
  end

  def extract_all(_), do: []

  @doc """
  Strips Mermaid code blocks from a response, leaving only the text.

  Useful for displaying the response without the raw diagram code.

  ## Examples

      iex> MermaidParser.strip_diagrams("Check this:\\n```mermaid\\nA-->B\\n```\\nCool right?")
      "Check this:\\n\\nCool right?"
  """
  @spec strip_diagrams(String.t()) :: String.t()
  def strip_diagrams(response) when is_binary(response) do
    response
    |> String.replace(@mermaid_regex, "")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  def strip_diagrams(response), do: response
end
