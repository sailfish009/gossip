defmodule Gossip.Channels do
  @moduledoc """
  Context for channels
  """

  import Ecto.Query

  alias Gossip.Channels.Channel
  alias Gossip.Repo
  alias Gossip.Versions

  @type opts :: Keyword.t()
  @type name :: String.t()
  @type id :: integer()

  @doc """
  Create a new channel
  """
  @spec create(map()) :: {:ok, Channel.t()}
  def create(attributes) do
    changeset = %Channel{} |> Channel.changeset(attributes)

    case Repo.insert(changeset) do
      {:ok, channel} ->
        broadcast_channel_create(channel.id)
        {:ok, channel}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Ensure a channel exists
  """
  @spec ensure_channel(name()) :: {:ok, name()} | {:error, name()}
  def ensure_channel(name) do
    case Repo.get_by(Channel, name: name) do
      nil ->
        case create(%{name: name}) do
          {:ok, channel} ->
            {:ok, channel.name}

          {:error, _} ->
            {:error, name}
        end

      channel ->
        {:ok, channel.name}
    end
  end

  @doc """
  Get all channels
  """
  @spec all(opts()) :: [Channel.t()]
  def all(opts \\ []) do
    Channel
    |> maybe_include_hidden(opts)
    |> Repo.all()
  end

  defp maybe_include_hidden(query, opts) do
    case Keyword.get(opts, :include_hidden, false) do
      false ->
        query |> where([c], c.hidden == false)

      true ->
        query
    end
  end

  @doc """
  Get a channel by name
  """
  @spec get(name()) :: {:ok, Channel.t()} | {:error, :not_found}
  @spec get(id()) :: {:ok, Channel.t()} | {:error, :not_found}
  def get(channel_id) when is_integer(channel_id) do
    case Repo.get(Channel, channel_id) do
      nil ->
        {:error, :not_found}

      channel ->
        {:ok, channel}
    end
  end

  def get(channel) do
    case Repo.get_by(Channel, name: channel) do
      nil ->
        {:error, :not_found}

      channel ->
        {:ok, channel}
    end
  end

  @doc """
  Load the list of blocked channel names

  File is in `priv/channels/block-list.txt`

  This file is a newline separated list of downcased names
  """
  @spec name_blocklist() :: [name()]
  def name_blocklist() do
    blocklist = Path.join(:code.priv_dir(:gossip), "channels/block-list.txt")
    {:ok, blocklist} = File.read(blocklist)

    blocklist
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
  end

  defp broadcast_channel_create(channel_id) do
    with {:ok, channel} <- get(channel_id),
         {:ok, version} <- Versions.log("create", channel) do
      Web.Endpoint.broadcast("system:backbone", "channels/new", version)
    else
      _ ->
        :ok
    end
  end
end
