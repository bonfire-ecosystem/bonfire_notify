defmodule Bonfire.Notify.WebPush.Payload do
  @moduledoc """
  Represents a web push payload.
  """

  @enforce_keys [:title, :body]
  defstruct title: "Bonfire",
            body: "",
            tag: nil,
            require_interaction: false,
            url: nil

  @type t :: %__MODULE__{
          title: String.t(),
          body: String.t(),
          tag: String.t() | nil,
          require_interaction: boolean(),
          url: String.t() | nil
        }

  @doc """
  Serializes a web push payload.
  """
  @spec serialize(t()) :: String.t() | no_return()
  def serialize(%__MODULE__{} = payload) do
    payload
    |> Map.from_struct()
    |> Poison.encode!()
  end
end
