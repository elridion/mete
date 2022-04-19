defmodule Mete.Connection.Udp do
  @behaviour Mete.Connection

  defstruct [
    :host,
    :port,
    :socket
  ]

  @impl true
  def init(config) do
    case :gen_udp.open(0, [:binary, active: true]) do
      {:ok, socket} ->
        connection = %__MODULE__{
          host: convert_to_charlist(config.host),
          port: config.port,
          socket: socket
        }

        {:ok, connection}

      error ->
        error
    end
  end

  @impl true
  def transmit(payload, %__MODULE__{} = connection) do
    :gen_udp.send(connection.socket, connection.host, connection.port, payload)
  end

  @impl true
  def batch_size(%__MODULE__{socket: socket}) do
    case :inet.getopts(socket, [:buffer]) do
      {:ok, [buffer: buffer]} -> buffer
      _ -> 8192
    end
  end

  defp convert_to_charlist(string) when is_binary(string) do
    String.to_charlist(string)
  end

  defp convert_to_charlist(char_lst) when is_list(char_lst) do
    char_lst
  end
end
