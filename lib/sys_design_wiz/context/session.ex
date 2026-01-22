defmodule SysDesignWiz.Context.Session do
  @moduledoc """
  Ecto schema for conversation sessions.

  A session holds the system prompt and groups related messages together.
  Sessions are identified by a unique session_id (typically a UUID from the browser).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SysDesignWiz.Context.Message

  @type t :: %__MODULE__{
          id: integer() | nil,
          session_id: String.t(),
          system_prompt: String.t(),
          messages: [Message.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "sessions" do
    field(:session_id, :string)
    field(:system_prompt, :string)

    has_many(:messages, Message, foreign_key: :session_id)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new session.
  """
  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(session, attrs) do
    session
    |> cast(attrs, [:session_id, :system_prompt])
    |> validate_required([:session_id, :system_prompt])
    |> unique_constraint(:session_id)
  end

  @doc """
  Updates the updated_at timestamp to mark session as active.
  """
  @spec touch_changeset(t()) :: Ecto.Changeset.t()
  def touch_changeset(session) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(session, updated_at: now)
  end
end
