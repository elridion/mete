if Code.ensure_loaded?(:hackney) do
  defmodule Mete.Connection.Hackney do
    @behaviour Mete.Connection

    import IO, only: [iodata_to_binary: 1]

    alias Mete.Config

    defstruct [
      :token,
      :uri,
      :influx_version
    ]

    @impl true
    def init(%Config{influx_version: 1} = config) do
      if is_binary(config.database) do
        uri = Config.uri(config)

        {:ok, %__MODULE__{influx_version: 1, uri: uri}}
      else
        {:error, :database_missing}
      end
    end

    def init(%Config{influx_version: 2} = config) do
      if is_binary(config.bucket) and is_binary(config.organisation) and is_binary(config.token) do
        uri = Config.uri(config)

        {:ok, %__MODULE__{influx_version: 2, uri: uri, token: "Token #{config.token}"}}
      else
        {:error, :database_missing}
      end
    end

    @impl true
    def transmit(payload, %__MODULE__{uri: uri, token: token}) do
      body = iodata_to_binary(payload)

      headers =
        if is_binary(token) do
          [{"Authorization", token}, {"Content-Type", "text-plain; charset=utf-8"}]
        else
          []
        end

      :hackney.post(uri, headers, body)

      :ok
    end

    @impl true
    def batch_size(_) do
      nil
    end
  end
end
