defmodule Mete.Connection do
  @moduledoc false
  use GenServer

  require Logger

  import IO, only: [iodata_length: 1]
  import Mete.Config

  alias Mete.Config

  @callback init(%Mete.Config{}) :: {:ok, term()} | {:error, reason :: String.t()}
  @callback transmit(payload :: iodata(), connection :: term()) :: :ok
  @callback batch_size(term()) :: nil | pos_integer()

  defstruct [
    :conn,
    :config,
    :batch
  ]

  # @default_conf [
  #   host: "localhost",
  #   port: 8089,
  #   protocol: :udp,
  #   database: nil,
  #   tags: [],
  #   batch: true
  # ]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: Mete, spawn_opt: [fullsweep_after: 50])
  rescue
    _e in ArgumentError ->
      {:error, :unexpected}
  end

  @impl true
  def init(args) do
    config = config(args)
    state = %__MODULE__{config: config}

    Logger.debug(["Started Mete with:\n\n", inspect(state, pretty: true)])

    case spawn_conn(state.config) do
      {:error, reason} ->
        Logger.error(["Cannot spawn connection ", inspect(reason)])
        {:ok, %__MODULE__{state | conn: :error}}

      conn ->
        batch_conf =
          config
          |> batch_size(conn)
          |> batch_config()

        state = %__MODULE__{state | conn: conn, batch: batch_conf}
        {:ok, state, {:continue, :init}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    flush(state)
  end

  @impl true
  def handle_continue(:init, state) do
    Process.flag(:trap_exit, true)

    unless is_nil(state.batch) do
      schedule_flush()
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:write, {measurement, tags, fields, timestamp}}, state) do
    batch_conf =
      {measurement, Mete.Utils.into_tags(tags, state.config.tags), fields, timestamp}
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
    # check if there are messages in the queue
    # if so we don't have to flush by hand
    case Process.info(self(), :message_queue_len) do
      {:message_queue_len, 0} ->
        {:noreply, flush(state)}

      _ ->
        {:noreply, state}
    end
  after
    # unless this batch was configured to be nil from the beginning
    # this schedules a new flush
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

  defp schedule_flush do
    Process.send_after(self(), :"$mete_flush", :timer.seconds(30))
  end

  ## API calls

  def spawn_conn(%Config{protocol: protocol} = config) do
    adapter_module = adapter_module(protocol)

    case apply(adapter_module, :init, [config]) do
      {:ok, %^adapter_module{} = conn} ->
        conn

      {:error, _error} = error ->
        error

      unexpected ->
        Logger.critical([
          "Expected a wellbahaved return of either {:error, some_error} or {:ok, adapter_struct} and instead got ",
          inspect(unexpected)
        ])

        {:error, :unexpected}
    end
  end

  def transmit(payload, adapter)

  def transmit(payload, %adapter_module{} = adapter) do
    apply(adapter_module, :transmit, [payload, adapter])
  end

  def transmit(_payload, :error) do
    :ok
  end

  # {[], 0, 8192}
  def batch(payload, batch_conf)

  def batch(nil, nil) do
    #  if flush is triggered on an non batching conn.
    {:batch, nil, nil}
  end

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

  defp batch_config(batch_size) when is_integer(batch_size) and batch_size > 0 do
    {[], 0, batch_size}
  end

  defp batch_config(_) do
    nil
  end
end
