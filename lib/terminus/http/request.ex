defmodule Terminus.HTTP.Request do
  @moduledoc false

  defstruct method: nil,
            path: nil,
            headers: [],
            body: nil

  @type t :: %__MODULE__{
    method: String.t,
    path: String.t,
    headers: list,
    body: binary
  }
end