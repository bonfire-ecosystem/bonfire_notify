defmodule Bonfire.Notify.WebPush.SubscriptionWorkerTest do
  use Bonfire.Notify.DataCase, async: true

  import Mox

  alias Ecto.Adapters.SQL.Sandbox

  import Bonfire.Common.Config, only: [repo: 0]

  alias Bonfire.Notify.WebPush
  alias Bonfire.Notify.WebPush.Payload
  alias Bonfire.Notify.WebPush.SubscriptionWorker

  import Bonfire.Notify.Test.FakeHelpers

  @valid_data """
    {
      "endpoint": "https://endpoint.test",
      "expirationTime": null,
      "keys": {
        "p256dh": "p256dh",
        "auth": "auth"
      }
    }
  """

  setup :verify_on_exit!

  setup do
    user = fake_user!()
    {:ok, sub_data} = WebPush.subscribe(user.id, @valid_data)

    {:ok, worker_pid} = SubscriptionWorker.start_link([sub_data.digest, sub_data.subscription])

    # Explicitly allow the worker access to the mock adapter and repo
    Mox.allow(Bonfire.Notify.WebPush.TestAdapter, self(), worker_pid)
    Sandbox.allow(repo(), self(), worker_pid)

    {:ok, Map.merge(sub_data, %{user: user, worker_pid: worker_pid})}
  end

  describe "send_web_push/2" do
    test "makes a request",
         %{
           digest: digest,
           subscription: subscription,
           worker_pid: worker_pid
         } do
      payload = %Payload{title: "Bonfire", body: "Hello"}
      expect_response(201, payload, subscription)
      assert :ok == SubscriptionWorker.send_web_push(digest, payload)

      # Wait for the cast call to complete
      :sys.get_state(worker_pid)
    end

    test "deletes the subscription if request returns a 404",
         %{
           user: %{id: user_id},
           digest: digest,
           subscription: subscription,
           worker_pid: worker_pid
         } do
      payload = %Payload{title: "Bonfire", body: "Hello"}
      expect_response(404, payload, subscription)
      assert :ok == SubscriptionWorker.send_web_push(digest, payload)

      ref = Process.monitor(worker_pid)
      assert_receive {:DOWN, ^ref, :process, ^worker_pid, :normal}

      assert %{} = WebPush.get_subscriptions([user_id])
    end

    test "deletes the subscription if request returns a 410",
         %{
           user: %{id: user_id},
           digest: digest,
           subscription: subscription,
           worker_pid: worker_pid
         } do
      payload = %Payload{title: "Bonfire", body: "Hello"}
      expect_response(410, payload, subscription)
      assert :ok == SubscriptionWorker.send_web_push(digest, payload)

      ref = Process.monitor(worker_pid)
      assert_receive {:DOWN, ^ref, :process, ^worker_pid, :normal}

      assert %{} = WebPush.get_subscriptions([user_id])
    end

    test "retries until success",
         %{
           digest: digest,
           subscription: subscription,
           worker_pid: worker_pid
         } do
      payload = %Payload{title: "Bonfire", body: "Hello"}
      expect_response(500, payload, subscription)
      expect_response(201, payload, subscription)
      assert :ok == SubscriptionWorker.send_web_push(digest, payload)

      # Wait for the cast call to complete
      :sys.get_state(worker_pid)
    end

    test "stops retrying after max attempts",
         %{
           digest: digest,
           subscription: subscription
         } do
      payload = %Payload{title: "Bonfire", body: "Hello"}
      expect_response(500, payload, subscription, max_attempts())
      assert :ok == SubscriptionWorker.send_web_push(digest, payload)

      # This is hack to give the retries enough time to loop.
      # Is there a better way?
      #
      # The :sys.get_state(worker_pid) technique does not work here,
      # because it ends up slipping into the mailbox ahead of the
      # final retry messages, which causes the test process to end
      # before the retries have a chance to finish.
      Process.sleep(1000)
    end
  end

  defp expect_response(status_code, payload, subscription, n \\ 1) do
    Bonfire.Notify.WebPush.TestAdapter
    |> expect(:make_request, n, fn ^payload, ^subscription ->
      {:ok, %HTTPoison.Response{status_code: status_code}}
    end)
  end

  defp max_attempts do
    Bonfire.Common.Config.get(Bonfire.Notify.WebPush)[:max_attempts]
  end
end
