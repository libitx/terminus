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
  post "/block" do
    {status, body} = case get_req_header(conn, "token") do
      ["test"] -> {200, File.read!("test/mocks/bitbus-block.json")}
      _ -> {403, File.read!("test/mocks/unauthorized.json")}
    end
    stream_resp(conn, status, body)
  end

  # Bitbus /status mock
  get "/status" do
    body = File.read!("test/mocks/bitbus-status.json")
    stream_resp(conn, 200, body)
  end

  # Bitsocket /crawl mock
  post "/crawl" do
    {status, body} = case get_req_header(conn, "token") do
      ["test"] -> {200, File.read!("test/mocks/bitsocket-crawl.json")}
      _ -> {403, File.read!("test/mocks/unauthorized.json")}
    end
    stream_resp(conn, status, body)
  end

  # Bitsocket /listen mock
  get "/s/:query" do
    data = %{type: "push", data: [%{"tx" => %{"h" => "741bcaf3f5ec40a48d78fcc0314ce260547122e8f69c51cedbf9e56ec3388c35"}}]}
    chunk = %SSE.Chunk{data: Jason.encode!(data)}
    SSE.stream(conn, {[:test], chunk})
  end

  # BitFS fetch
  get "/13513153d455cdb394ce01b5238f36e180ea33a9ccdf5a9ad83973f2d423684a.out.0.4" do
    body = File.read!("test/mocks/bitfs-fetch.json")
    stream_resp(conn, 200, body)
  end

  # BitFS fetch 404
  get "/notfound" do
    stream_resp(conn, 404, "Not found")
  end

  
  # Setup the streaming response
  defp stream_resp(conn, status, body) do
    conn
    |> put_resp_header("content-length", Integer.to_string(byte_size(body)))
    |> send_chunked(status)
    |> stream_chunks(body)
  end

  # Breakup and stream the body in chunks
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