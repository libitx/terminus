# Terminus

![Terminus - Crawl and subscribe to Bitcoin transaction events using Bitbus, Bitsocket and BitFS.](https://github.com/libitx/terminus/raw/master/media/poster.jpg)

![Hex.pm](https://img.shields.io/hexpm/v/terminus?color=informational)
![GitHub](https://img.shields.io/github/license/libitx/terminus?color=informational)
![GitHub Workflow Status](https://img.shields.io/github/workflow/status/libitx/terminus/Elixir CI)

Terminus allows you to crawl and subscribe to Bitcoin transaction events and download binary data from transactions, using a combination of [Bitbus](https://bitbus.network) and [Bitsocket](https://bitsocket.network), and [BitFS](https://bitfs.network).

Terminus provides a single unified interface for querying Planaria corp APIs in a highly performant manner. Each request is a `GenStage` process, enabling you to create powerful concurrent data flows. Terminus may well be the most powerful way of querying Bitcoin in the Universe!

* [Full documentation](https://hexdocs.pm/terminus)

## Installation

The package can be installed by adding `terminus` to your list of dependencies in `mix.exs`.

```elixir
def deps do
  [
    {:terminus, "~> 0.0.3"}
  ]
end
```

## Getting started

Terminus can be used as a simple API client, or a turbo-charged, concurrent multi-stream Bitcoin scraper on steroids. You decide.

The following documented modules, are the primary ways of using Terminus.

* [`Terminus.Bitbus`](https://hexdocs.pm/terminus/Terminus.Bitbus.html) - functions for crawling and query confirmed Bitcoin transactions.
* [`Terminus.Bitsocket`](https://hexdocs.pm/terminus/Terminus.Bitsocket.html) - query mempool transactions and listen to realtime transaction events.
* [`Terminus.BitFS`](https://hexdocs.pm/terminus/Terminus.BitFS.html) - fetch binary data blobs embedded in Bitcoin transactions.
* [`Terminus.Omni`](https://hexdocs.pm/terminus/Terminus.Omni.html) - conveniently fetch confirmed and mempool transactions together.
* [`Terminus.Planaria`](https://hexdocs.pm/terminus/Terminus.Planaria.html) - run Bitcoin scraper processes under your application's supervision tree.

## License

[MIT License](https://github.com/libitx/terminus/blob/master/LICENSE.md).

© Copyright 2020 libitx.