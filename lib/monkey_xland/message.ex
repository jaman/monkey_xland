defmodule MonkeyXland.Message do
  @moduledoc """
  A message on screen: what an actor says, or what the narrator prints.

  A message is split into pages at its wait codes (`0xFF 3`). A page is shown for 60
  jiffies plus `char_increment` (variable 37) per character, or until its voice clip
  (`voices`, one per page, see `MonkeyXland.Voices`) ends if that is longer; then the
  next page replaces it, and after the last the message ends. The player can end a page
  early.

  `pages` hold lines, a line a list of `{text, colour}` runs. `position` is where the
  page shown now was laid out, in screen pixels: lines are centred on its x when
  `center` is set, otherwise start at it, and run down from its y. `shown` is that page
  with its lines broken to fit: a line breaks at its last space once it is wider than
  the space to the right edge (`right` minus x minus 1), or, centred, than twice the
  smaller of that and x. `@` is padding: it is neither drawn nor measured.
  """

  alias MonkeyXland.{Actor, Assets, Objects, World}
  alias MonkeyXland.Scumm.Charset

  @enforce_keys [:actor, :pages, :settings]
  defstruct [
    :actor,
    :pages,
    :settings,
    page: 0,
    delay: 0,
    position: {0, 0},
    shown: [],
    voices: []
  ]

  @type run :: {binary(), byte()}
  @typedoc "The script variables timing and placing text: `char_increment` (37) and `talk_y` (54)."
  @type env :: %{char_increment: integer(), talk_y: integer()}
  @type t :: %__MODULE__{
          actor: non_neg_integer(),
          pages: [[[run()]]],
          settings: map(),
          page: non_neg_integer(),
          delay: integer(),
          position: {integer(), integer()},
          shown: [[run()]],
          voices: [MonkeyXland.Voices.voice() | nil]
        }

  @base_delay 60

  @doc """
  The pages of a message whose parts are already read (see `GrogVM.Text`), coloured
  `color` until a colour code changes it.
  """
  @spec pages(World.t(), [term()], byte()) :: [[[run()]]]
  def pages(world, parts, color) do
    {pages, _color} =
      Enum.reduce(parts, {[[[]]], color}, fn part, {pages, color} ->
        add(world, part, pages, color)
      end)

    pages
    |> Enum.reverse()
    |> Enum.map(fn lines -> lines |> Enum.reverse() |> Enum.map(&Enum.reverse/1) end)
  end

  @doc "The plain text of a message's parts, every code left out or written as text."
  @spec plain(World.t(), [term()]) :: binary()
  def plain(world, parts) do
    world |> pages(parts, 0) |> List.flatten() |> Enum.map_join(&elem(&1, 0))
  end

  @doc "A message by `actor` (0xFF for none) with text-slot `settings`, laid out and timed for its first page."
  @spec new(World.t(), env(), non_neg_integer(), map(), [term()], [
          MonkeyXland.Voices.voice() | nil
        ]) :: t()
  def new(world, env, actor, settings, parts, voices \\ []) do
    color = talk_color(world, actor, settings)

    %__MODULE__{
      actor: actor,
      pages: pages(world, parts, color),
      settings: settings,
      voices: voices
    }
    |> show_page(world, env, 0)
  end

  @doc "The voice of the page shown, or `nil`."
  @spec voice(t()) :: MonkeyXland.Voices.voice() | nil
  def voice(%__MODULE__{voices: voices, page: page}), do: Enum.at(voices, page)

  @doc "Lays out page `index` and starts its delay."
  @spec show_page(t(), World.t(), env(), non_neg_integer()) :: t()
  def show_page(%__MODULE__{} = message, world, env, index) do
    page = Enum.at(message.pages, index, [])
    characters = page |> List.flatten() |> Enum.map(&byte_size(elem(&1, 0))) |> Enum.sum()
    delay = @base_delay + env.char_increment * characters
    position = position(world, env, message)

    shown =
      wrap(page, Assets.charset(message.settings.charset), max_width(message.settings, position))

    %{
      message
      | page: index,
        delay: max(delay, voice_jiffies(Enum.at(message.voices, index))),
        position: position,
        shown: shown
    }
  end

  defp max_width(%{right: right, center: true}, {x, _y}), do: min(right - x - 1, x) * 2
  defp max_width(%{right: right}, {x, _y}), do: right - x - 1

  defp wrap(page, nil, _max_width), do: page
  defp wrap(page, charset, max_width), do: Enum.flat_map(page, &wrap_line(&1, charset, max_width))

  defp wrap_line(runs, charset, max_width) do
    characters = for {text, color} <- runs, <<code <- text>>, do: {code, color}
    characters |> break(charset, max_width, 1, [], nil) |> Enum.map(&to_runs/1)
  end

  defp break([], _charset, _max_width, _width, line, _space), do: [Enum.reverse(line)]

  defp break([{code, _color} = character | rest], charset, max_width, width, line, space) do
    width = width + advance(charset, code)
    line = [character | line]
    space = if code == ?\s, do: length(line) - 1, else: space

    if width > max_width and space != nil do
      {kept, carried} = line |> Enum.reverse() |> Enum.split(space)
      [kept | break(tl(carried) ++ rest, charset, max_width, 1, [], nil)]
    else
      break(rest, charset, max_width, width, line, space)
    end
  end

  defp advance(%Charset{glyphs: glyphs}, code) do
    case Map.get(glyphs, code) do
      nil -> 0
      glyph -> glyph.width + glyph.x
    end
  end

  defp to_runs(characters) do
    characters
    |> Enum.chunk_by(&elem(&1, 1))
    |> Enum.map(fn [{_code, color} | _rest] = chunk ->
      {for({code, _color} <- chunk, into: <<>>, do: <<code>>), color}
    end)
  end

  @doc "Whether there is a page after the one shown."
  @spec more?(t()) :: boolean()
  def more?(%__MODULE__{page: page, pages: pages}), do: page + 1 < length(pages)

  @doc "The lines of the page shown, each `{x, y, runs}` in screen pixels."
  @spec lines(t(), Charset.t() | nil) :: [{integer(), integer(), [run()]}]
  def lines(_message, nil), do: []

  def lines(%__MODULE__{shown: shown, position: {x, y}, settings: settings}, %Charset{} = charset) do
    shown
    |> Enum.with_index()
    |> Enum.map(fn {runs, row} ->
      {line_x(settings, charset, runs, x), y + row * charset.height, runs}
    end)
  end

  defp add(_world, part, [lines | pages], color) when is_binary(part),
    do: {[append(lines, {unpadded(part), color}) | pages], color}

  defp add(_world, :newline, [lines | pages], color), do: {[[[] | lines] | pages], color}
  defp add(_world, :wait, pages, color), do: {[[[]] | pages], color}
  defp add(_world, {:color, new}, pages, _color), do: {pages, new}

  defp add(_world, {:int, value}, [lines | pages], color),
    do: {[append(lines, {Integer.to_string(value), color}) | pages], color}

  defp add(world, {:verb, verb}, [lines | pages], color),
    do: {[append(lines, {verb_name(world, verb), color}) | pages], color}

  defp add(world, {:name, number}, [lines | pages], color),
    do: {[append(lines, {name(world, number), color}) | pages], color}

  defp add(world, {:string, number}, [lines | pages], color),
    do: {[append(lines, {unpadded(Map.get(world.strings, number, "")), color}) | pages], color}

  defp add(_world, _code, pages, color), do: {pages, color}

  defp append([line | lines], run), do: [[run | line] | lines]

  @doc "Text with its `@` padding taken out."
  @spec unpadded(binary()) :: binary()
  def unpadded(text), do: String.replace(text, "@", "")

  defp verb_name(world, verb) do
    case Map.get(world.verbs, verb) do
      %{name: name} when is_binary(name) -> name
      _none -> ""
    end
  end

  defp name(world, number) do
    case World.actor(world, number) do
      %Actor{name: name} -> name
      nil -> Objects.name(world, number)
    end
  end

  defp talk_color(world, actor, settings) do
    case World.actor(world, actor) do
      %Actor{talk_color: color} -> color
      nil -> settings.color
    end
  end

  defp voice_jiffies(nil), do: 0
  defp voice_jiffies(%{seconds: seconds}), do: round(seconds * 60)

  defp position(world, env, %__MODULE__{actor: actor, settings: %{overhead: true} = settings}) do
    case World.actor(world, actor) do
      %Actor{room: room} = speaker when room == world.room and room != 0 ->
        overhead(world, env.talk_y, speaker)

      _elsewhere ->
        {settings.x, settings.y}
    end
  end

  defp position(_world, _env, %__MODULE__{settings: settings}), do: {settings.x, settings.y}

  defp overhead(world, talk_y, %Actor{
         x: x,
         y: y,
         elevation: elevation,
         scale: {_scale_x, scale_y}
       }) do
    screen_x = x - (world.camera.x - div(World.screen_width(), 2))
    base_y = y - elevation

    screen_y =
      if talk_y < 0 do
        shift = div(scale_y * talk_y, 0xFF)
        base_y + div(talk_y - shift, 2) + shift
      else
        talk_y
      end

    {screen_x |> max(80) |> min(World.screen_width() - 80), max(screen_y, 1)}
  end

  defp line_x(%{center: true}, charset, runs, x) do
    width = Charset.width(charset, Enum.map_join(runs, &elem(&1, 0)))
    (x - div(width, 2)) |> max(0) |> min(World.screen_width() - width)
  end

  defp line_x(_settings, _charset, _runs, x), do: x
end
