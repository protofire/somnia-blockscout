defmodule Explorer.Repo.Migrations.CreatePendingTransactionOperations do
  use Ecto.Migration

  def change do
    create table(:pending_transaction_operations, primary_key: false) do
      add(:transaction_hash, :bytea, null: false, primary_key: true)
      timestamps()
    end
  end
end
