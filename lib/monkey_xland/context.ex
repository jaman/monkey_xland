defmodule MonkeyXland.Context do
  @moduledoc """
  The world inside a running `GrogVM.Ctx`, and the engine variables by name.

      world = MonkeyXland.Context.world(ctx)
      ctx = MonkeyXland.Context.put_var(ctx, :room, 33)
  """

  alias GrogVM.Ctx
  alias MonkeyXland.{Vars, World}

  @doc "The world."
  @spec world(Ctx.t()) :: World.t()
  def world(%Ctx{host: world}), do: world

  @doc "Replaces the world."
  @spec put_world(Ctx.t(), World.t()) :: Ctx.t()
  def put_world(%Ctx{} = ctx, %World{} = world), do: %{ctx | host: world}

  @doc "Changes the world with `fun`."
  @spec update(Ctx.t(), (World.t() -> World.t())) :: Ctx.t()
  def update(%Ctx{host: world} = ctx, fun), do: %{ctx | host: fun.(world)}

  @doc "An engine variable's value, by name."
  @spec var(Ctx.t(), atom()) :: integer()
  def var(ctx, name), do: GrogVM.var(ctx, Vars.number(name))

  @doc "Sets an engine variable, by name."
  @spec put_var(Ctx.t(), atom(), integer()) :: Ctx.t()
  def put_var(ctx, name, value), do: GrogVM.put_var(ctx, Vars.number(name), value)

  @doc "The values `MonkeyXland.Message` needs from the script variables."
  @spec text_env(Ctx.t()) :: MonkeyXland.Message.env()
  def text_env(ctx), do: %{char_increment: var(ctx, :char_increment), talk_y: GrogVM.var(ctx, 54)}
end
