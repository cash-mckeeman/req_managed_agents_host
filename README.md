# req_managed_agents_host

Durable single-node session host for [`req_managed_agents`](https://hex.pm/packages/req_managed_agents).

Turns RMA's per-call `ReqManagedAgents.Session` into a supervised, crash-survivable,
idle-detachable hosted session keyed by a caller-supplied external id. One public
function — `ReqManagedAgents.Host.send_message/3` — finds, starts, or reattaches the
right session, runs it to a terminal, and returns the RMA `SessionResult`, with the
session's upstream identity durably persisted so a BEAM restart resumes the conversation.

> Quickstart, store options (ETS / DETS), and the durability model are documented as the
> package is built out.

## License

Apache-2.0.
