defmodule SysDesignWiz.Context.Message do
  @moduledoc """
  Ecto schema for conversation messages.

  Messages belong to a session and have a role (user/assistant/system)
  and content.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias SysDesignWiz.Context.Session

  @type t :: %__MODULE__{
          id: integer() | nil,
          session_id: integer(),
          role: String.t(),
          content: String.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "messages" do
    field(:role, :string)
    field(:content, :string)

    belongs_to(:session, Session, foreign_key: :session_id)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a new message.
  """
  @spec changeset(t() | %__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:session_id, :role, :content])
    |> validate_required([:session_id, :role, :content])
    |> validate_inclusion(:role, ["user", "assistant", "system", "tool"])
    |> foreign_key_constraint(:session_id)
  end
end
