defmodule Terminus.HTTP.SSEMessage do
  @moduledoc false

  defstruct id: nil, event: "message", data: ""
  
  @type t :: %__MODULE__{
    id: String.t,
    event: String.t,
    data: binary
  }
end