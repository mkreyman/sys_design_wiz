defmodule SysDesignWiz.Repo.Migrations.CreateSessionsAndMessages do
  use Ecto.Migration

  def change do
    create table(:sessions) do
      add(:session_id, :string, null: false)
      add(:system_prompt, :text, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:sessions, [:session_id]))
    create(index(:sessions, [:updated_at]))

    create table(:messages) do
      add(:session_id, references(:sessions, on_delete: :delete_all), null: false)
      add(:role, :string, null: false)
      add(:content, :text, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:messages, [:session_id]))
    create(index(:messages, [:inserted_at]))
  end
end
