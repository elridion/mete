defmodule Mete.Connection do
  @moduledoc false
  use GenServer

  require Logger

  import Mete.Protocol

  defstruct [
    :host,
    :port,
    :protocol,
    :conn,
    :database,
    # :timestamp,
    :tags,
    :path
  ]

  @default_conf [
    host: "localhost",
    port: 8089,
    protocol: :udp,
    database: nil,
    # timestamp: nil,
    tags: []
  ]

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: Mete)
  end

  def init(args) do
    config =
      Keyword.merge(
        @default_conf,
        Keyword.merge(Application.get_all_env(:mete), args)
      )

    state = %__MODULE__{
      host: Keyword.get(config, :host),
      port: Keyword.get(config, :port),
      database: Keyword.get(config, :database),
      protocol: Keyword.get(config, :protocol),
      # timestamp: Keyword.get(config, :timestamp),
      tags: Keyword.get(config, :tags)
    }

    require Logger
    Logger.info(["Started Mete with:\n\n", inspect(state, pretty: true)])

    case spawn_conn(state) do
      {:error, reason} ->
        Logger.error(["Cloud not spawn connection ", inspect(reason)])
        {:ok, %{state | conn: :error}}

      conn ->
        {:ok, %{state | conn: conn}}
    end
  end

  def handle_cast({:write, {measurement, tags, fields, timestamp}}, state) do
    {measurement, Mete.Utils.into_tags(tags, state.tags), fields, timestamp}
    |> Mete.Protocol.encode()
    |> transmit(state)

    {:noreply, state}
  end

  def spawn_conn(%__MODULE__{protocol: protocol} = state) do
    spawn_conn(protocol, state)
  end

  def spawn_conn(:http, %{datanase: nil}) do
    {:error, "http requires a database"}
  end

  def spawn_conn(:http, %{host: host, port: port, database: db}) do
    :inets.start()

    uri =
      host
      |> URI.parse()
      |> Map.put(:port, port)
      |> Map.update(:scheme, nil, &(&1 || :http))
      |> Map.update(:path, nil, fn path ->
        cond do
          String.ends_with?(path, "/write") ->
            path

          String.ends_with?(path, "/") ->
            path <> "write"

          true ->
            path <> "/write"
        end
      end)
      |> Map.put(:query, URI.encode_query(%{"db" => db}))
      |> URI.to_string()
      |> String.to_charlist()

    {:http, uri}
  end

  def spawn_conn(:udp, %{host: host, port: port}) do
    case :gen_udp.open(0, [:binary, active: true]) do
      {:ok, socket} ->
        buffer =
          case :inet.getopts(socket, [:buffer]) do
            {:ok, [buffer: buffer]} -> buffer
            _ -> 8192
          end

        {:udp, {socket, convert_to_charlist(host), port, buffer}}

      error ->
        error
    end
  end

  def spawn_conn(_, _) do
    {:error, "unknown protocol"}
  end

  def transmit(payload, conn)

  def transmit(payload, %__MODULE__{conn: conn}) do
    transmit(payload, conn)
  end

  def transmit(payload, {:udp, {socket, host, port, _buffer}}) do
    :gen_udp.send(socket, host, port, payload)
  end

  def transmit(payload, {:http, uri}) do
    import IO, only: [iodata_to_binary: 1]

    :httpc.request(:post, {uri, [], 'text-plain', iodata_to_binary(payload)}, [], [])
  end

  def transmit(_payload, :error) do
    # :gen_udp.send(socket, host, port, payload)
    :ok
  end

  defp convert_to_charlist(string) when is_binary(string) do
    String.to_charlist(string)
  end

  defp convert_to_charlist(char_lst) when is_list(char_lst) do
    char_lst
  end
end
