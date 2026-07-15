defmodule ReqManagedAgents.Host.SessionServer do
  @moduledoc """
  Per-external-id GenServer driving one turn at a time through `ReqManagedAgents.Session.run/2`.

  Fresh (`Locator` has no `session_id` for this external id): opens with no `:session_id`
  opt; the provider mints one and `Session.run/2` returns it, which is persisted into a
  `Locator.Record`. Reattach (`Locator` already has a `session_id`): passes it back in as
  `:session_id`, so the provider consolidates into the existing upstream session and the
  request_response reattach seam delivers the message as a fresh `user.message` rather than a
  new kickoff. Either way a turn is exactly one `Session.run/2` call — no `Client`, no
  hand-sent events.

  Idle for `config.idle_timeout_ms` after replying to a turn: stops normally. The `Locator`
  row (and thus the upstream session id) survives the stop — the next `deliver/2` for the same
  external id starts a fresh server and reattaches instead of minting a new upstream session.
  """
  use GenServer

  alias ReqManagedAgents.Host.{Config, Locator}
  alias ReqManagedAgents.Host.Locator.Record
  alias ReqManagedAgents.{Session, SessionResult}

  @registry ReqManagedAgents.Host.Registry

  @enforce_keys [:external_id, :config]
  defstruct external_id: nil, config: nil, idle_ref: nil

  @type t :: %__MODULE__{
          external_id: Locator.external_id(),
          config: Config.t(),
          idle_ref: reference() | nil
        }

  @doc "Start the server for `external_id`, registered under `via/1`."
  @spec start_link({Locator.external_id(), Config.t()}) :: GenServer.on_start()
  def start_link({external_id, %Config{} = config}) do
    GenServer.start_link(__MODULE__, {external_id, config}, name: via(external_id))
  end

  @doc "Run one turn: deliver `message` and block for the resulting `SessionResult`."
  @spec deliver(GenServer.server(), String.t()) :: {:ok, SessionResult.t()} | {:error, term()}
  def deliver(server, message), do: GenServer.call(server, {:send, message}, :infinity)

  @doc "The `Registry`-backed name a server for `external_id` runs under."
  @spec via(Locator.external_id()) :: {:via, Registry, {module(), Locator.external_id()}}
  def via(external_id), do: {:via, Registry, {@registry, external_id}}

  @impl true
  def init({external_id, config}),
    do: {:ok, %__MODULE__{external_id: external_id, config: config}}

  @impl true
  def handle_call({:send, message}, _from, %__MODULE__{} = state) do
    state = cancel_idle(state)
    result = run_turn(state, message)
    if match?({:ok, _}, result), do: persist(state, result)
    {:reply, result, arm_idle(state)}
  end

  @impl true
  def handle_info(:idle_timeout, %__MODULE__{} = state), do: {:stop, :normal, state}

  # ── turn ────────────────────────────────────────────────────────────────

  @spec run_turn(t(), String.t()) :: {:ok, SessionResult.t()} | {:error, term()}
  defp run_turn(%__MODULE__{config: cfg, external_id: external_id}, message) do
    base = [prompt: message, handler: cfg.handler]

    opts =
      case existing_session_id(cfg.store, external_id) do
        nil -> base
        session_id -> [{:session_id, session_id} | base]
      end ++ agent_opts(cfg) ++ cfg.provider_opts

    Session.run(cfg.provider, opts)
  end

  @spec existing_session_id(Config.store(), Locator.external_id()) :: String.t() | nil
  defp existing_session_id(store, external_id) do
    case Locator.fetch(store, external_id) do
      {:ok, %Record{session_id: session_id}} -> session_id
      :error -> nil
    end
  end

  # Typed handles thread straight into `Session.run/2`'s `lift_handle` unpacking — omit the
  # key entirely rather than pass a bare `nil`, so an absent handle never shadows an explicit
  # `:agent_id`/`:environment_id` a caller put in `provider_opts`.
  @spec agent_opts(Config.t()) :: keyword()
  defp agent_opts(%Config{agent: agent, environment: environment}) do
    []
    |> maybe_put(:agent, agent)
    |> maybe_put(:environment, environment)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  @spec persist(t(), {:ok, SessionResult.t()}) :: :ok
  defp persist(
         %__MODULE__{config: cfg, external_id: external_id},
         {:ok, %SessionResult{session_id: session_id}}
       ) do
    record =
      case Locator.fetch(cfg.store, external_id) do
        {:ok, %Record{} = existing} ->
          %Record{existing | session_id: session_id}

        :error ->
          Record.new(external_id,
            session_id: session_id,
            agent_id: handle_id(cfg.agent, :agent_id),
            environment_id: handle_id(cfg.environment, :environment_id)
          )
      end

    Locator.put(cfg.store, record)
  end

  defp handle_id(nil, _key), do: nil
  defp handle_id(handle, key), do: Map.fetch!(handle, key)

  # ── idle timer ─────────────────────────────────────────────────────────

  @spec cancel_idle(t()) :: t()
  defp cancel_idle(%__MODULE__{idle_ref: nil} = state), do: state

  defp cancel_idle(%__MODULE__{idle_ref: ref} = state) do
    Process.cancel_timer(ref)
    %__MODULE__{state | idle_ref: nil}
  end

  @spec arm_idle(t()) :: t()
  defp arm_idle(%__MODULE__{config: cfg} = state) do
    %__MODULE__{state | idle_ref: Process.send_after(self(), :idle_timeout, cfg.idle_timeout_ms)}
  end
end
