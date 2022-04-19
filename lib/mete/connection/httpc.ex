defmodule Mete.Connection.Httpc do
  @behaviour Mete.Connection

  import IO, only: [iodata_to_binary: 1]

  alias Mete.Config

  defstruct [:uri]

  @impl true
  def init(%Config{} = config) do
    uri = Config.uri(config)

    {:ok, %__MODULE__{uri: uri}}
  end

  @impl true
  def transmit(payload, %__MODULE__{uri: uri}) do
    :httpc.request(:post, {uri, [], 'text-plain', iodata_to_binary(payload)}, [], [])
  end

  @impl true
  def batch_size(_) do
    nil
  end
end
