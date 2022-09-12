defmodule Bonfire.Notify.WebPush do
  @moduledoc """
  The subsystem for recording push subscriptions and send them.
  """

  use Supervisor

  import Ecto.Query

  import Bonfire.Common.Config, only: [repo: 0]

  alias Ecto.Changeset
  alias Bonfire.Notify.WebPush.Payload
  alias Bonfire.Notify.WebPush.UserSubscription
  alias Bonfire.Notify.WebPush.Subscription
  alias Bonfire.Notify.WebPush.SubscriptionSupervisor
  alias Bonfire.Notify.WebPush.UserSupervisor
  alias Bonfire.Notify.WebPush.UserWorker

  @doc """
  Starts the process supervisor.
  """
  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      UserSupervisor,
      SubscriptionSupervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Registers a push subscription.
  """
  @spec subscribe(String.t(), String.t()) ::
          {:ok, %{digest: String.t(), subscription: Subscription.t()}}
          | {:error, :invalid_keys | :parse_error | :database_error}
  def subscribe(user_id, data) do
    case parse_subscription(data) do
      {:ok, subscription} ->
        subscription
        |> persist(user_id, data)
        |> after_persist()

      err ->
        err
    end
  end

  defp persist(subscription, user_id, data) do
    result =
      %Schema{}
      |> Changeset.change(%{user_id: user_id, data: data})
      |> Changeset.change(%{digest: compute_digest(data)})
      |> repo().insert(on_conflict: :nothing)

    {result, subscription}
  end

  defp after_persist({{:ok, record}, subscription}) do
    {:ok, %{digest: record.digest, subscription: subscription}}
  end

  defp after_persist({_, _}) do
    {:error, :database_error}
  end

  defp compute_digest(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16()
  end

  @doc """
  Fetches all subscriptions for a list of user ids.
  """
  @spec get_subscriptions([String.t()]) :: %{
          optional(String.t()) => [Subscription.t()]
        }
  def get_subscriptions(user_ids) do
    user_ids
    |> build_query()
    |> repo().many()
    |> parse_records()
  end

  defp build_query(user_ids) do
    from(r in Schema, where: r.user_id in ^user_ids)
  end

  defp parse_records(records) do
    records
    |> Enum.map(fn %Schema{user_id: user_id, data: data} ->
      case parse_subscription(data) do
        {:ok, subscription} -> [user_id, subscription]
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(&List.first/1, &List.last/1)
  end

  @doc """
  Parses raw stringified JSON subscription data.
  """
  @spec parse_subscription(String.t()) ::
          {:ok, Subscription.t()}
          | {:error, :invalid_keys}
          | {:error, :parse_error}
  def parse_subscription(data) do
    Subscription.parse(data)
  end

  @doc """
  Sends a notification to a particular subscription.
  """
  @spec send_web_push(String.t(), Payload.t()) ::
          :ok | :ignore | {:error, any()}
  def send_web_push(user_id, %Payload{} = payload) do
    user_id
    |> UserSupervisor.start_worker()
    |> handle_start_worker(user_id, payload)
  end

  defp handle_start_worker({:ok, _pid}, user_id, payload) do
    UserWorker.send_web_push(user_id, payload)
  end

  defp handle_start_worker({:ok, _pid, _info}, user_id, payload) do
    UserWorker.send_web_push(user_id, payload)
  end

  defp handle_start_worker({:error, {:already_started, _pid}}, user_id, payload) do
    UserWorker.send_web_push(user_id, payload)
  end

  defp handle_start_worker(err, _, _), do: err
end
