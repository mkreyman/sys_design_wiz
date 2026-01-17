defmodule SysDesignWiz.Formatting do
  @moduledoc """
  Number and text formatting utilities.
  """

  @doc """
  Formats a number with comma delimiters for readability.

  ## Examples

      iex> SysDesignWiz.Formatting.number_to_delimited(1234567)
      "1,234,567"

      iex> SysDesignWiz.Formatting.number_to_delimited(1234.56)
      "1,235"

      iex> SysDesignWiz.Formatting.number_to_delimited(nil)
      "N/A"
  """
  def number_to_delimited(nil), do: "N/A"

  def number_to_delimited(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  def number_to_delimited(number) when is_float(number) do
    number |> round() |> number_to_delimited()
  end

  def number_to_delimited(number), do: "#{number}"
end
