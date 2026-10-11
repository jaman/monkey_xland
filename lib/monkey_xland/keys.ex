defmodule MonkeyXland.Keys do
  @moduledoc """
  The keys the game is played with, as actions: one action per key, named `:key_<name>`,
  each with the terminal key that presses it and the code the scripts read.

  Letters, digits, space, `.` (skips the text on screen), Escape (skips a cutscene),
  Enter and Backspace.
  """

  @letters for code <- ?a..?z, do: {:"key_#{<<code>>}", String.to_atom(<<code>>), code}
  @digits for code <- ?0..?9, do: {:"key_#{<<code>>}", String.to_atom(<<code>>), code}
  @named [
    {:key_space, :" ", ?\s},
    {:key_period, :., ?.},
    {:key_escape, :escape, 27},
    {:key_enter, :enter, 13},
    {:key_backspace, :backspace, 8}
  ]
  @keys @letters ++ @digits ++ @named
  @codes Map.new(@keys, fn {action, _key, code} -> {action, code} end)

  @doc "Every key action."
  @spec actions() :: [atom()]
  def actions, do: Enum.map(@keys, &elem(&1, 0))

  @doc "Each key action with the terminal keys that press it."
  @spec keymap() :: %{atom() => [atom()]}
  def keymap, do: Map.new(@keys, fn {action, key, _code} -> {action, [key]} end)

  @doc "The code the scripts read for a key action, or `nil` for any other action."
  @spec code(atom()) :: non_neg_integer() | nil
  def code(action), do: Map.get(@codes, action)
end
