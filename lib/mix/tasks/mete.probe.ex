defmodule Mix.Tasks.Mete.Probe do
  use Mix.Task

  defmodule ProbeServer do
    use GenServer
    @moduledoc false

    def init(args \\ []) do
      interval = args[:interval] || :timer.seconds(1)
      {:ok, interval, {:continue, :tick}}
    end

    def handle_continue(:tick, interval) do
      tick(interval)
    end

    def handle_info(:tick, interval) do
      tick(interval)
    end

    defp tick(interval) do
      Process.send_after(self(), :tick, interval)

      memory()
      cpu()
      mete()

      {:noreply, interval}
    end

    defp memory do
      Mete.write("memory", :erlang.memory())
    end

    defp cpu do
      :scheduler.sample_all()
      |> :scheduler.utilization()
      |> Enum.each(fn entry ->
        entry
        |> case do
          {measurement, id, util, _perc} ->
            Mete.write("scheduler_" <> Atom.to_string(measurement), [id: id], util)

          {measurement, util, _perc} ->
            Mete.write("scheduler_" <> Atom.to_string(measurement), util)

          _ ->
            :ok
        end
      end)
    end

    def mete do
      pid = GenServer.whereis(Mete)

      if is_pid(pid) do
        values =
          pid
          |> Process.info()
          |> Keyword.take([:heap_size, :stack_size])

        Mete.write("mete", values)
      end
    end
  end

  @shortdoc "Transmits Measurements"

  @moduledoc """
  Transmits Measurements to Tests the configuration
  """

  def run(args) do
    GenServer.start_link(ProbeServer, [])
    Mix.Tasks.Run.run(run_args() ++ args)
  end

  defp run_args do
    if iex_running?(), do: [], else: ["--no-halt"]
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) and IEx.started?()
  end
end
