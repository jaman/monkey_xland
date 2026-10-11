defmodule MonkeyXland.Pak.Entry do
  @moduledoc """
  One file in a `KAPL` archive: its path, its position from the archive's data offset, its
  size in bytes and whether the archive marks it compressed.
  """

  @enforce_keys [:name, :position, :size, :compressed?]
  defstruct [:name, :position, :size, :compressed?]

  @type t :: %__MODULE__{
          name: String.t(),
          position: non_neg_integer(),
          size: non_neg_integer(),
          compressed?: boolean()
        }
end
