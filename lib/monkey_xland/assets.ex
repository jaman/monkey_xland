defmodule MonkeyXland.Assets do
  @moduledoc """
  The owner's game, read once and kept for the life of the node: the install, every room
  decoded, every script compiled, the room each object's code lives in, and the three
  Special Edition wave banks — `music` (the CD tracks, named `trackN`), `effects` (the
  original sound effects, named `N_sound_SBL_…` for sound `N`) and `speech` — with
  `speech_info` saying which clip speaks which line. Costumes, fonts and sounds are decoded the first time they are asked for.

      {:ok, assets} = MonkeyXland.Assets.load(game_dir)
      MonkeyXland.Assets.get().rooms[33]
  """

  alias MonkeyXland.Install
  alias MonkeyXland.Scumm.{Charset, Costume, Resources, Room, Sound}
  alias MonkeyXland.Xact.WaveBank

  @enforce_keys [
    :install,
    :rooms,
    :globals,
    :room_code,
    :object_rooms,
    :music,
    :effects,
    :effect_entries,
    :speech,
    :speech_info,
    :speech_cues
  ]
  defstruct @enforce_keys

  @type room_code :: %{
          entry: module() | nil,
          exit: module() | nil,
          locals: %{non_neg_integer() => module()},
          objects: %{non_neg_integer() => {module(), %{byte() => non_neg_integer()}}}
        }
  @type t :: %__MODULE__{
          install: Install.t(),
          rooms: %{non_neg_integer() => Room.t()},
          globals: %{non_neg_integer() => module()},
          room_code: %{non_neg_integer() => room_code()},
          object_rooms: %{non_neg_integer() => non_neg_integer()},
          music: WaveBank.t(),
          effects: WaveBank.t(),
          effect_entries: %{non_neg_integer() => WaveBank.entry()},
          speech: WaveBank.t(),
          speech_info: MonkeyXland.SpeechInfo.t(),
          speech_cues: %{String.t() => non_neg_integer()}
        }

  @global_scripts 1..199

  @doc "Reads the install at `dir`, decodes every room, compiles every script, and keeps it all."
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(dir) do
    with {:ok, install} <- Install.load(dir),
         {:ok, rooms} <- rooms(install),
         {:ok, globals} <- globals(install),
         {:ok, room_code} <- room_code(rooms),
         {:ok, music} <- WaveBank.open(Install.audio_path(install, "MusicOriginal.xwb")),
         {:ok, effects} <- WaveBank.open(Install.audio_path(install, "SFXOriginal.xwb")),
         {:ok, speech} <- WaveBank.open(Install.audio_path(install, "Speech.xwb")),
         {:ok, speech_info} <-
           MonkeyXland.SpeechInfo.read(Install.audio_path(install, "speech.info")) do
      assets = %__MODULE__{
        install: install,
        rooms: rooms,
        globals: globals,
        room_code: room_code,
        object_rooms: object_rooms(rooms),
        music: music,
        effects: effects,
        effect_entries: effects_by_sound(effects),
        speech: speech,
        speech_info: speech_info,
        speech_cues:
          for(
            entry <- speech.entries,
            entry.name != nil,
            into: %{},
            do: {entry.name, entry.index}
          )
      }

      :persistent_term.put(__MODULE__, assets)
      {:ok, assets}
    end
  end

  @doc """
  The music bank's entry for audio track `track` as the sound resources number it: the
  bank names the CD's tracks, where track 1 holds data, so audio track `n` is `track(n+1)`.
  """
  @spec cd_track(non_neg_integer()) :: WaveBank.entry() | nil
  def cd_track(track), do: WaveBank.entry(get().music, "track#{track + 1}")

  @doc "The loaded game; raises when `load/1` has not run."
  @spec get() :: t()
  def get, do: :persistent_term.get(__MODULE__)

  @doc "Whether a game has been loaded."
  @spec loaded?() :: boolean()
  def loaded?, do: :persistent_term.get(__MODULE__, nil) != nil

  @doc "Costume `number`, decoded once."
  @spec costume(non_neg_integer()) :: Costume.t() | nil
  def costume(number),
    do: cached({:costume, number}, fn -> decode(:costume, number, &Costume.parse/1) end)

  @doc "Font `number`, decoded once."
  @spec charset(non_neg_integer()) :: Charset.t() | nil
  def charset(number),
    do: cached({:charset, number}, fn -> decode(:charset, number, &Charset.parse/1) end)

  @doc "Sound `number`'s forms, decoded once."
  @spec sound(non_neg_integer()) :: Sound.t() | nil
  def sound(number),
    do: cached({:sound, number}, fn -> decode(:sound, number, &Sound.parse/1) end)

  defp cached(key, build) do
    case :persistent_term.get({__MODULE__, key}, :unread) do
      :unread -> tap(build.(), &:persistent_term.put({__MODULE__, key}, &1))
      value -> value
    end
  end

  defp decode(kind, number, parse) do
    with {:ok, body} <- Install.fetch(get().install, kind, number),
         {:ok, value} <- parse.(body) do
      value
    else
      _missing -> nil
    end
  end

  defp rooms(install) do
    install.resources
    |> Resources.rooms()
    |> Task.async_stream(&{&1, Install.room(install, &1)}, timeout: :infinity)
    |> Enum.reduce_while({:ok, %{}}, fn
      {:ok, {number, {:ok, room}}}, {:ok, acc} -> {:cont, {:ok, Map.put(acc, number, room)}}
      {:ok, {number, {:error, reason}}}, _acc -> {:halt, {:error, {:room, number, reason}}}
    end)
  end

  defp globals(install) do
    found =
      for number <- @global_scripts,
          {:ok, body} <- [Install.fetch(install, :script, number)],
          do: {number, body}

    compiled =
      found |> Enum.map(fn {_number, body} -> {body, [0]} end) |> GrogVM.Compiler.load_all()

    collect(Enum.zip(Enum.map(found, &elem(&1, 0)), compiled))
  end

  defp room_code(rooms) do
    programs =
      for {number, room} <- rooms,
          {key, code, entries} <- room_programs(room),
          do: {{number, key}, code, entries}

    compiled =
      programs
      |> Enum.map(fn {_key, code, entries} -> {code, entries} end)
      |> GrogVM.Compiler.load_all()

    with {:ok, modules} <- collect(Enum.zip(Enum.map(programs, &elem(&1, 0)), compiled)) do
      {:ok, Map.new(rooms, fn {number, room} -> {number, code_of(number, room, modules)} end)}
    end
  end

  defp room_programs(%Room{} = room) do
    scripts =
      [{:entry, room.entry_script, [0]}, {:exit, room.exit_script, [0]}]
      |> Enum.reject(fn {_key, code, _entries} -> code == <<>> end)

    locals = for {number, code} <- room.local_scripts, do: {{:local, number}, code, [0]}

    objects =
      for object <- room.objects,
          map_size(object.verbs) > 0,
          do:
            {{:object, object.number}, object.script, object.verbs |> Map.values() |> Enum.uniq()}

    scripts ++ locals ++ objects
  end

  defp code_of(number, %Room{} = room, modules) do
    %{
      entry: Map.get(modules, {number, :entry}),
      exit: Map.get(modules, {number, :exit}),
      locals:
        for(
          {number_local, _code} <- room.local_scripts,
          into: %{},
          do: {number_local, Map.fetch!(modules, {number, {:local, number_local}})}
        ),
      objects:
        for(
          object <- room.objects,
          map_size(object.verbs) > 0,
          into: %{},
          do:
            {object.number,
             {Map.fetch!(modules, {number, {:object, object.number}}), object.verbs}}
        )
    }
  end

  defp effects_by_sound(%WaveBank{} = bank) do
    for entry <- bank.entries,
        [number | _rest] <- [String.split(entry.name || "", "_")],
        {sound, ""} <- [Integer.parse(number)],
        into: %{} do
      {sound, entry}
    end
  end

  defp object_rooms(rooms) do
    for {number, room} <- rooms, object <- room.objects, into: %{}, do: {object.number, number}
  end

  defp collect(pairs) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn
      {key, {:ok, module}}, {:ok, acc} -> {:cont, {:ok, Map.put(acc, key, module)}}
      {key, {:error, reason}}, _acc -> {:halt, {:error, {:compile, key, reason}}}
    end)
  end
end
