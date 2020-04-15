# Terminus

Terminus is an Elixir library to help you crawl and subscribe to Bitcoin transaction events using [Bitbus](https://bitbus.network) and [Bitsocket](https://bitsocket.network), and download binary data from [BitFS](https://bitfs.network).

> **terminus** &mdash; noun
> * the end of a railway or other transport route, or a station at such a point; a terminal.
> * a final point in space or time; an end or extremity.

Terminus provides a single unified interface for crawling and querying Bitbus, Bitsocket and BitFS in a highly performant manner. Each request is a `GenStage` process, enabling you to create powerful concurrent data flows. Terminus may well be the most powerful way of querying Bitcoin in the Universe!

* [Full documentation](https://hexdocs.pm/terminus)

## Installation

The package can be installed by adding `terminus` to your list of dependencies in `mix.exs`.

```elixir
def deps do
  [
    {:terminus, "~> 0.0.1"}
  ]
end
```

## Usage

Terminus can be used as a simple client for crawling and querying Bitbus and Bitsocket APIs, and fetching binary data from BitFS. For simple examples, refer to the [full documentation](https://hexdocs.pm/terminus).

### Streams
  
Most Terminus functions return a streaming enumerable, allowing you to compose data processing pipelines and operations.

```elixir
iex> Terminus.Bitbus.crawl!(query, token: token)
...> |> Stream.map(&Terminus.BitFS.scan_tx/1)
...> |> Stream.each(&save_to_db/1)
...> |> Stream.run
:ok
``` 

### Concurrency

Under the hood, each Terminus request is a `GenStage` producer process, and the bare `pid` can be returned. This allows you to take full advantage of Elixir's concurrency, by either using with your own `GenStage` consumers or using a tool like `Flow` to create powerful concurrent pipelines.

```elixir
# One stream of transactions will be distributed across eight concurrent
# processes for mapping and saving the data.
iex> {:ok, pid} = Terminus.Bitbus.crawl(query, token: token, stage: true)
iex> Flow.from_stages([pid], stages: 8)
...> |> Flow.map(&Terminus.BitFS.scan_tx/1)
...> |> Flow.map(&transform_tx/1)
...> |> Flow.map(&save_to_db/1)
...> |> Flow.run
:ok
```

## License

[MIT License](https://github.com/libitx/terminus/blob/master/LICENSE.md).

© Copyright 2020 libitx.