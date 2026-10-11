defmodule MonkeyXland.Scumm.Room.BoxMatrix do
  @moduledoc """
  The walk-box route table from `BOXM`.

  For each box, in order, a list of `{first, last, next}`: to reach any box numbered
  `first..last` from this box, walk to box `next` first. On disk each box's list is
  three-byte entries ended by `0xFF`.
  """

  @type route :: {first :: byte(), last :: byte(), next :: byte()}
  @type t :: [[route()]]

  @doc "Parses a `BOXM` body."
  @spec parse(binary()) :: t()
  def parse(body), do: body |> rows([], []) |> Enum.reverse()

  @doc "Returns the box to walk to next when going from box `from` to box `to`, if any."
  @spec next_box(t(), non_neg_integer(), non_neg_integer()) :: {:ok, byte()} | :error
  def next_box(matrix, from, to) do
    matrix
    |> Enum.at(from, [])
    |> Enum.find(fn {first, last, _next} -> to in first..last//1 end)
    |> found()
  end

  defp found({_first, _last, next}), do: {:ok, next}
  defp found(nil), do: :error

  defp rows(<<0xFF, rest::binary>>, row, acc), do: rows(rest, [], [Enum.reverse(row) | acc])

  defp rows(<<first, last, next, rest::binary>>, row, acc),
    do: rows(rest, [{first, last, next} | row], acc)

  defp rows(_rest, [], acc), do: acc
  defp rows(_rest, row, acc), do: [Enum.reverse(row) | acc]
end
