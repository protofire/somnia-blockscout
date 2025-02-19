defmodule Explorer.Repo.Migrations.ChangeAddressNonceToBigint do
  use Ecto.Migration

  def change do
    alter table("addresses") do
      modify :nonce, :bigint, from: :integer
    end
  end
end
