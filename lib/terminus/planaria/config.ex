defmodule Terminus.Planaria.Config do
  @moduledoc """
  TODO
  """

  defstruct token: nil, poll: 300, from: nil, query: %{}

  @typedoc "TODO"
  @type t :: %__MODULE__{
    token: String.t,
    poll: integer,
    from: integer,
    query: map
  }
end