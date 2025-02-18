defmodule Explorer.Repo.Migrations.ChangeTransactionNonceToBigint do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      modify :nonce, :bigint, from: :integer
    end
  end
end
