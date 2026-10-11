defmodule MonkeyXland.Scumm.Block do
  @moduledoc """
  SCUMM v5 blocks: a four-byte tag, a big-endian 32-bit length that counts the 8-byte
  header, then the body.

  `children/1` splits a body into `{tag, body}` pairs in file order; `find/2` and
  `find_all/2` pick children by tag; `decrypt/1` undoes the `0x69` XOR applied to every byte
  of `.000` and `.001`.
  """

  import Bitwise

  @chunk_size 65_536

  @type tag :: <<_::32>>
  @type child :: {tag(), binary()}

  @doc "Splits `bytes` into its blocks. Trailing bytes too short for a block are ignored."
  @spec children(binary()) :: [child()]
  def children(bytes), do: for({tag, _position, body} <- positioned(bytes), do: {tag, body})

  @doc """
  Splits `bytes` into its blocks, each with the position of its body within `bytes`.
  """
  @spec positioned(binary()) :: [{tag(), non_neg_integer(), binary()}]
  def positioned(bytes), do: bytes |> collect(0, []) |> Enum.reverse()

  @doc "Returns the body of the first child tagged `tag`."
  @spec find(binary() | [child()], tag()) :: {:ok, binary()} | :error
  def find(bytes, tag) when is_binary(bytes), do: bytes |> children() |> find(tag)

  def find(children, tag) do
    children |> List.keyfind(tag, 0) |> found()
  end

  @doc "Returns the bodies of every child tagged `tag`, in file order."
  @spec find_all(binary() | [child()], tag()) :: [binary()]
  def find_all(bytes, tag) when is_binary(bytes), do: bytes |> children() |> find_all(tag)
  def find_all(children, tag), do: for({^tag, body} <- children, do: body)

  @doc "Reads the block starting at the beginning of `bytes`."
  @spec read(binary()) :: {:ok, child()} | :error
  def read(<<tag::binary-4, length::32, rest::binary>>)
      when length >= 8 and length - 8 <= byte_size(rest) do
    {:ok, {tag, binary_part(rest, 0, length - 8)}}
  end

  def read(_bytes), do: :error

  @doc "XORs every byte with `0x69`."
  @spec decrypt(binary()) :: binary()
  def decrypt(bytes), do: bytes |> decrypt_chunks([]) |> IO.iodata_to_binary()

  defp decrypt_chunks(<<chunk::binary-size(@chunk_size), rest::binary>>, acc),
    do: decrypt_chunks(rest, [xor_chunk(chunk) | acc])

  defp decrypt_chunks(chunk, acc), do: Enum.reverse([xor_chunk(chunk) | acc])

  defp xor_chunk(<<>>), do: <<>>

  defp xor_chunk(chunk) do
    size = byte_size(chunk)
    <<value::size(^size)-unit(8)>> = chunk
    <<mask::size(^size)-unit(8)>> = :binary.copy(<<0x69>>, size)
    <<bxor(value, mask)::size(size)-unit(8)>>
  end

  defp found({_tag, body}), do: {:ok, body}
  defp found(nil), do: :error

  defp collect(<<tag::binary-4, length::32, rest::binary>>, position, acc)
       when length >= 8 and length - 8 <= byte_size(rest) do
    body_size = length - 8
    <<body::binary-size(^body_size), tail::binary>> = rest
    collect(tail, position + length, [{tag, position + 8, body} | acc])
  end

  defp collect(_bytes, _position, acc), do: acc
end
