defmodule MockServer do
  use Plug.Router
  plug Plug.Parsers, [
    parsers: [:json],
    pass:  ["text/*"],
    json_decoder: Jason
  ]
  plug :match
  plug :dispatch

  # Bitbus /status mock
  get "/status" do
    body = File.read!("test/mocks/status.json")
    stream_resp(conn, 200, body)
  end

  # Bitbus /status mock
  post "/block" do
    {status, body} = case get_req_header(conn, "token") do
      ["test"] -> {200, File.read!("test/mocks/block.json")}
      _ -> {403, File.read!("test/mocks/unauthorized.json")}
    end
    stream_resp(conn, status, body)
  end


  # Helpers

  defp stream_resp(conn, status, body) do
    conn
    |> put_resp_header("content-length", Integer.to_string(byte_size(body)))
    |> send_chunked(status)
    |> stream_chunks(body)
  end

  defp stream_chunks(conn, body) when is_binary(body) do
    chunks = Regex.scan(~r/.{1,192}/s, body)
    |> Enum.map(&Enum.join/1)
    |> Kernel.++(["\n"])
    stream_chunks(conn, chunks)
  end
  defp stream_chunks(conn, []), do: conn
  defp stream_chunks(conn, [head | tail]) do
    case chunk(conn, head) do
      {:ok, conn} -> stream_chunks(conn, tail)
      {:error, :closed} -> conn
    end
  end
end