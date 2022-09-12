defmodule Bonfire.Notify.WebPush.Subscription do
  @moduledoc """
  Represents a web push subscription.
  """

  @enforce_keys [:endpoint, :keys]
  defstruct [:endpoint, :keys]

  @type t :: %__MODULE__{
          endpoint: String.t(),
          keys: %{
            auth: String.t(),
            p256dh: String.t()
          }
        }

  # Poison.decode() seems to have a buggy typespec
  @dialyzer {:nowarn_function, after_decode: 1}

  @doc """
  Parses a raw subscription payload.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, :invalid_keys | :parse_error}
  def parse(data) do
    data
    |> Poison.decode()
    |> after_decode()
  end

  defp after_decode(
         {:ok,
          %{
            "endpoint" => endpoint,
            "keys" => %{"auth" => auth, "p256dh" => p256dh}
          }}
       ) do
    client_auth_token = Base.url_decode64!(auth, padding: false)
    IO.inspect(client_auth_token: client_auth_token)
    IO.inspect(byte_size(client_auth_token))
    IO.inspect(byte_size("AUTH"))

    IO.inspect(
      subscription_decoded: %{
        endpoint: endpoint,
        keys: %{auth: auth, p256dh: p256dh}
      }
    )

    {:ok, %__MODULE__{endpoint: endpoint, keys: %{auth: auth, p256dh: p256dh}}}
  end

  defp after_decode({:ok, _}) do
    {:error, :invalid_keys}
  end

  defp after_decode(_) do
    {:error, :parse_error}
  end
end
