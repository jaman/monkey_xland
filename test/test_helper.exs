exclude = if System.get_env("MONKEYXLAND_GAME"), do: [], else: [:game]
ExUnit.start(exclude: exclude)
