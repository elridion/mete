defmodule Mete.Scheduler do
  use GenServer

  require Logger

  defstruct children: [], conn_args: [], ets: nil

  @scale_up_threshhold 500
  @scale_down_threshhold 50
  @scale_interval :timer.seconds(10)

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # Process.flag(:trap_exit, true)

    :ets.new(Mete, [:named_table, {:read_concurrency, true}])
    state = spawn_connection(%__MODULE__{ets: Mete})

    schedule_scaling()

    {:ok, state}
  end

  @impl true
  def handle_continue(:spawn, state) do
    state = spawn_connection(state)

    {:noreply, state}
  end

  # def handle_info({:EXIT, _pid, _stacktrace}, state) do
  #   {:noreply, state}
  # end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply, __scheduler_info__(state), state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _stacktrace}, state) do
    :ets.delete(state.ets, pid)

    case :lists.keyfind(pid, 1, state.children) do
      {_pid, ^ref} -> :ok
      {_pid, _ref} -> Logger.warning("Removed Mete child with unmatching monitor reference")
      false -> :ok
    end

    children = :lists.keydelete(pid, 1, state.children)
    state = %__MODULE__{state | children: children}

    {:noreply, state}
  end

  def handle_info(:"$mete_scale", state) do
    [connections: connections, mean_queue_length: mean_msg_queue_len] = __scheduler_info__(state)

    state =
      cond do
        mean_msg_queue_len >= @scale_up_threshhold ->
          # SacleUp
          spawn_connection(state)

        mean_msg_queue_len <= @scale_down_threshhold and connections > 1 ->
          # ScaleDown
          close_connection(state)

        true ->
          # Noop
          state
      end

    schedule_scaling()

    {:noreply, state}
  end

  ##  internal

  defp schedule_scaling do
    Process.send_after(self(), :"$mete_scale", @scale_interval)
  end

  defp spawn_connection(%__MODULE__{} = state) do
    # {:ok, pid} = Mete.Connection.start_link(state.conn_args)
    {:ok, pid} = Mete.Connection.start(state.conn_args)
    ref = Process.monitor(pid)

    state = %__MODULE__{state | children: [{pid, ref} | state.children]}
    :ets.insert(state.ets, {pid})

    state
  end

  defp close_connection(%__MODULE__{} = state) do
    {pid, _ref, _len} =
      state
      |> children_queues()
      |> Enum.sort(fn {_, _, len1}, {_, _, len2} -> len1 <= len2 end)
      |> hd()

    :ets.delete(state.ets, pid)
    # GenServer.cast(pid, :quit)
    children = :lists.keydelete(pid, 1, state.children)

    GenServer.stop(pid, :normal)

    %__MODULE__{state | children: children}
  end

  defp __scheduler_info__(state) do
    msg_queue_len =
      state
      |> children_queues()
      |> Enum.reduce(0, fn {_pid, _ref, len}, acc -> acc + len end)

    connections = Enum.count(state.children)
    mean_msg_queue_len = msg_queue_len / connections

    [connections: connections, mean_queue_length: mean_msg_queue_len]
  end

  defp children_queues(state) do
    Enum.map(state.children, fn {pid, ref} ->
      case Process.info(pid, :message_queue_len) do
        {:message_queue_len, len} -> {pid, ref, len}
        nil -> {pid, ref, 0}
      end
    end)
  end
end
