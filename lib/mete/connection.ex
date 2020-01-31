defmodule Mete.Connection do
  @moduledoc false
  use GenServer

  require Logger

  import Mete.Protocol
  import IO, only: [iodata_length: 1]

  defstruct [
    :host,
    :port,
    :protocol,
    :conn,
    :database,
    :tags,
    :path,
    :batch
  ]

  @default_conf [
    host: "localhost",
    port: 8089,
    protocol: :udp,
    database: nil,
    tags: [],
    batch: true
  ]

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: Mete, spawn_opt: [fullsweep_after: 50])
  rescue
    _e in ArgumentError ->
      {:error, :unexpected}
  end

  @impl true
  def init(args) do
    config =
      Keyword.merge(
        @default_conf,
        Keyword.merge(Application.get_all_env(:mete), args)
      )

    batch = batch_config(config[:batch])

    state = %__MODULE__{
      host: Keyword.get(config, :host),
      port: Keyword.get(config, :port),
      database: Keyword.get(config, :database),
      protocol: Keyword.get(config, :protocol),
      tags: Keyword.get(config, :tags),
      batch: batch
    }

    require Logger
    Logger.debug(["Started Mete with:\n\n", inspect(state, pretty: true)])

    case spawn_conn(state) do
      {:error, reason} ->
        Logger.error(["Cannot spawn connection ", inspect(reason)])
        {:ok, %{state | conn: :error}}

      conn ->
        {:ok, %{state | conn: conn}, {:continue, :init}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    flush(state)
  end

  @impl true
  def handle_continue(:init, state) do
    Process.flag(:trap_exit, true)
    schedule_flush()
    {:noreply, state}
  end

  @impl true
  def handle_cast({:write, {measurement, tags, fields, timestamp}}, state) do
    batch_conf =
      {measurement, Mete.Utils.into_tags(tags, state.tags), fields, timestamp}
      |> Mete.Protocol.encode()
      |> batch(state.batch)
      |> case do
        {:transmit, payload, batch_conf} ->
          transmit(payload, state.conn)
          batch_conf

        {:batch, batch_conf} ->
          batch_conf
      end

    {:noreply, %__MODULE__{state | batch: batch_conf}}
  end

  @impl true
  def handle_info(:"$mete_flush", state) do
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, 0} ->
        {:noreply, flush(state)}

      _ ->
        {:noreply, state}
    end
  after
    unless is_nil(state.batch), do: schedule_flush()
  end

  def flush(state) do
    batch =
      case batch(nil, state.batch) do
        {:transmit, payload, batch} ->
          transmit(payload, state.conn)
          batch

        {:batch, batch} ->
          batch
      end

    %__MODULE__{state | batch: batch}
  end

  def schedule_flush do
    Process.send_after(self(), :"$mete_flush", :timer.seconds(30))
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
        # TODO: use udp buffer for batch buffer
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

  # {[], 0, 8192}
  def batch(payload, batch_conf)

  def batch(payload, nil) do
    {:transmit, payload, nil}
  end

  def batch(nil, batch_conf) do
    case batch_conf do
      {[], 0, _} -> {:batch, batch_conf}
      {payload, _, limit} -> {:transmit, payload, {[], 0, limit}}
    end
  end

  def batch(payload, batch_conf) when is_list(payload) do
    batch({payload, iodata_length(payload)}, batch_conf)
  end

  def batch({payload, payload_size}, {[], 0, limit} = batch_conf) do
    if payload_size < limit do
      {:batch, {payload, payload_size, limit}}
    else
      {:transmit, payload, batch_conf}
    end
  end

  def batch({payload, payload_size}, {buffer, buffer_size, limit}) do
    if payload_size + buffer_size + 1 < limit do
      {:batch,
       {
         [payload, ?\n | buffer],
         payload_size + buffer_size + 1,
         limit
       }}
    else
      {:transmit, buffer, {payload, payload_size, limit}}
    end
  end

  defp batch_config(conf) do
    case conf do
      false ->
        nil

      0 ->
        nil

      true ->
        {[], 0, 8192}

      limit ->
        if is_integer(limit) and limit > 0 do
          {[], 0, limit}
        else
          IO.warn("Invalid batch config: #{limit}")
          {[], 0, 8192}
        end
    end
  end

  defp convert_to_charlist(string) when is_binary(string) do
    String.to_charlist(string)
  end

  defp convert_to_charlist(char_lst) when is_list(char_lst) do
    char_lst
  end
end
