defmodule ReqManagedAgents.Host do
  @moduledoc """
  Durable single-node session host over `req_managed_agents`.

  `send_message/3` (added with the facade task) finds, starts, or reattaches the
  session for an external id, runs one turn to a terminal, and returns the RMA
  `ReqManagedAgents.SessionResult`. This is the whole public surface; it sits
  upstream of the cross-node durable tier.
  """
end
