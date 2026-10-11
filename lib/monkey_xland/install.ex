defmodule MonkeyXland.Install do
  @moduledoc """
  The owner's Special Edition install: the SCUMM index and resources read out of
  `Monkey1.pak`, decrypted and parsed, and the paths of the audio files.

      {:ok, install} = MonkeyXland.Install.load(game_dir)
      {:ok, room} = MonkeyXland.Install.room(install, 33)
  """

  alias MonkeyXland.Pak
  alias MonkeyXland.Scumm.{Block, Index, Resources, Room}

  @enforce_keys [:dir, :index, :resources]
  defstruct [:dir, :index, :resources]

  @type t :: %__MODULE__{dir: Path.t(), index: Index.t(), resources: Resources.t()}

  @pak "Monkey1.pak"
  @index_file "classic/en/monkey1.000"
  @resource_file "classic/en/monkey1.001"
  @required [
    "Monkey1.pak",
    "audio/MusicOriginal.xwb",
    "audio/SFXOriginal.xwb",
    "audio/Speech.xwb",
    "audio/speech.info"
  ]

  @doc """
  Reads and parses the index and resources from `dir`'s `Monkey1.pak`.

  `dir` must hold the Special Edition's `Monkey1.pak`, `audio/MusicOriginal.xwb`,
  `audio/SFXOriginal.xwb`, `audio/Speech.xwb` and `audio/speech.info`; without them it
  returns `{:error, {:not_installed, missing}}`, `missing` the files not found.
  """
  @spec load(Path.t()) :: {:ok, t()} | {:error, term()}
  def load(dir) do
    with :ok <- installed(dir),
         {:ok, pak} <- Pak.open(Path.join(dir, @pak)),
         {:ok, index_bytes, resource_bytes} <- read_scumm_files(pak),
         {:ok, index} <- index_bytes |> Block.decrypt() |> Index.parse(),
         {:ok, resources} <- resource_bytes |> Block.decrypt() |> Resources.parse() do
      {:ok, %__MODULE__{dir: dir, index: index, resources: resources}}
    end
  end

  @doc "Returns the path of a file under the install's `audio` directory."
  @spec audio_path(t(), String.t()) :: Path.t()
  def audio_path(%__MODULE__{dir: dir}, name), do: Path.join([dir, "audio", name])

  @doc "Reads and decodes room `number`."
  @spec room(t(), non_neg_integer()) :: {:ok, Room.t()} | {:error, term()}
  def room(%__MODULE__{resources: resources}, number) do
    with {:ok, body} <- Resources.room(resources, number) do
      Room.parse(number, body)
    end
  end

  @doc "Returns the body of a script, sound, costume or charset block."
  @spec fetch(t(), Index.kind(), non_neg_integer()) :: {:ok, binary()} | {:error, term()}
  def fetch(%__MODULE__{index: index, resources: resources}, kind, number) do
    Resources.fetch(resources, index, kind, number)
  end

  defp read_scumm_files(pak) do
    result =
      with {:ok, index_bytes} <- Pak.read(pak, @index_file),
           {:ok, resource_bytes} <- Pak.read(pak, @resource_file) do
        {:ok, index_bytes, resource_bytes}
      end

    Pak.close(pak)
    result
  end

  defp installed(dir) do
    case Enum.reject(@required, &File.regular?(Path.join(dir, &1))) do
      [] -> :ok
      absent -> {:error, {:not_installed, absent}}
    end
  end
end
