defmodule Explorer.Chain.Address.Counters do
  @moduledoc """
    Functions related to Explorer.Chain.Address counters
  """
  import Ecto.Query, only: [from: 2, limit: 2, select: 3, union: 2, where: 3]

  import Explorer.Chain,
    only: [select_repo: 1, wrapped_union_subquery: 1]

  alias Explorer.{Chain, Repo}

  alias Explorer.Counters.{
    AddressesCounter,
    AddressesWithBalanceCounter,
    AddressTokenTransfersCounter,
    AddressTransactionsCounter,
    AddressTransactionsGasUsageCounter
  }

  alias Explorer.Chain.{
    Address,
    Address.CurrentTokenBalance,
    Block,
    Hash,
    InternalTransaction,
    Log,
    TokenTransfer,
    Transaction,
    Withdrawal
  }

  alias Explorer.Chain.Cache.AddressesTabsCounters
  alias Explorer.Chain.Cache.Helper, as: CacheHelper
  alias Explorer.Chain.Celo.ElectionReward, as: CeloElectionReward

  require Logger

  @typep counter :: non_neg_integer() | nil

  @counters_limit 51
  @types [:validations, :transactions, :token_transfers, :token_balances, :logs, :withdrawals, :internal_transactions]
  @transactions_types [:transactions_from, :transactions_to, :transactions_contract]

  defp address_hash_to_logs_query(address_hash) do
    from(l in Log, where: l.address_hash == ^address_hash)
  end

  defp address_hash_to_validated_blocks_query(address_hash) do
    from(b in Block, where: b.miner_hash == ^address_hash)
  end

  def check_if_validated_blocks_at_address(address_hash, options \\ []) do
    select_repo(options).exists?(address_hash_to_validated_blocks_query(address_hash))
  end

  def check_if_logs_at_address(address_hash, options \\ []) do
    select_repo(options).exists?(address_hash_to_logs_query(address_hash))
  end

  def check_if_token_transfers_at_address(address_hash, options \\ []) do
    select_repo(options).exists?(from(tt in TokenTransfer, where: tt.from_address_hash == ^address_hash)) ||
      select_repo(options).exists?(from(tt in TokenTransfer, where: tt.to_address_hash == ^address_hash))
  end

  def check_if_tokens_at_address(address_hash, options \\ []) do
    select_repo(options).exists?(address_hash_to_token_balances_query(address_hash))
  end

  @spec check_if_withdrawals_at_address(Hash.Address.t()) :: boolean()
  def check_if_withdrawals_at_address(address_hash, options \\ []) do
    address_hash
    |> Withdrawal.address_hash_to_withdrawals_unordered_query()
    |> select_repo(options).exists?()
  end

  @doc """
  Gets from the cache the count of `t:Explorer.Chain.Address.t/0`'s where the `fetched_coin_balance` is > 0
  """
  @spec count_addresses_with_balance_from_cache :: non_neg_integer()
  def count_addresses_with_balance_from_cache do
    AddressesWithBalanceCounter.fetch()
  end

  @doc """
  Estimated count of `t:Explorer.Chain.Address.t/0`.

  Estimated count of addresses.
  """
  @spec address_estimated_count() :: non_neg_integer()
  def address_estimated_count(options \\ []) do
    count = CacheHelper.estimated_count_from("addresses", options)

    if is_nil(count), do: 0, else: max(count, 0)
  end

  @doc """
  Counts the number of all addresses.

  This function should be used with caution. In larger databases, it may take a
  while to have the return back.
  """
  def count_addresses do
    Repo.aggregate(Address, :count, timeout: :infinity)
  end

  @doc """
  Get the total number of transactions sent by the address with the given hash according to the last block indexed.

  We have to increment +1 in the last nonce result because it works like an array position, the first
  nonce has the value 0. When last nonce is nil, it considers that the given address has 0 transactions.
  """
  @spec total_transactions_sent_by_address(Hash.Address.t()) :: non_neg_integer()
  def total_transactions_sent_by_address(address_hash) do
    last_nonce =
      address_hash
      |> Transaction.last_nonce_by_address_query()
      |> Repo.one(timeout: :infinity)

    case last_nonce do
      nil -> 0
      value -> value + 1
    end
  end

  def address_hash_to_transaction_count_query(address_hash) do
    dynamic = Transaction.where_transactions_to_from(address_hash)

    Transaction
    |> where([transaction], ^dynamic)
  end

  @spec address_hash_to_transaction_count(Hash.Address.t()) :: non_neg_integer()
  def address_hash_to_transaction_count(address_hash) do
    query = address_hash_to_transaction_count_query(address_hash)

    Repo.aggregate(query, :count, :hash, timeout: :infinity)
  end

  @spec address_to_transaction_count(Address.t()) :: non_neg_integer()
  def address_to_transaction_count(address) do
    address_hash_to_transaction_count(address.hash)
  end

  @doc """
  Counts the number of `t:Explorer.Chain.Block.t/0` validated by the address with the given `hash`.
  """
  @spec address_to_validation_count(Hash.Address.t(), [Chain.api?()]) :: non_neg_integer()
  def address_to_validation_count(hash, options) do
    query = from(block in Block, where: block.miner_hash == ^hash, select: fragment("COUNT(*)"))

    select_repo(options).one(query)
  end

  @doc """
  Counts the number of addresses with fetched coin balance > 0.

  This function should be used with caution. In larger databases, it may take a
  while to have the return back.
  """
  def count_addresses_with_balance do
    Repo.one(
      Address.count_with_fetched_coin_balance(),
      timeout: :infinity
    )
  end

  @spec address_to_incoming_transaction_count(Hash.Address.t()) :: non_neg_integer()
  def address_to_incoming_transaction_count(address_hash) do
    to_address_query =
      from(
        transaction in Transaction,
        where: transaction.to_address_hash == ^address_hash
      )

    Repo.aggregate(to_address_query, :count, :hash, timeout: :infinity)
  end

  @doc """
    Calculates the total gas used by incoming transactions to a given address.

    This function queries the database for all transactions where the
    `to_address_hash` matches the provided `address_hash`, and sums up the
    `gas_used` for these transactions.

    ## Parameters
    - `address_hash`: The address hash to query for incoming transactions.

    ## Returns
    - The total gas used by incoming transactions, or `nil` if no transactions
      are found or if the sum is null.
  """
  @spec address_to_incoming_transaction_gas_usage(Hash.Address.t()) :: Decimal.t() | nil
  def address_to_incoming_transaction_gas_usage(address_hash) do
    to_address_query =
      from(
        transaction in Transaction,
        where: transaction.to_address_hash == ^address_hash
      )

    Repo.aggregate(to_address_query, :sum, :gas_used, timeout: :infinity)
  end

  @doc """
    Calculates the total gas used by outgoing transactions from a given address.

    This function queries the database for all transactions where the
    `from_address_hash` matches the provided `address_hash`, and sums up the
    `gas_used` for these transactions.

    ## Parameters
    - `address_hash`: the address to query.

    ## Returns
    - The total gas used, or `nil` if no transactions are found or if the sum is null.
  """
  @spec address_to_outcoming_transaction_gas_usage(Hash.Address.t()) :: Decimal.t() | nil
  def address_to_outcoming_transaction_gas_usage(address_hash) do
    to_address_query =
      from(
        transaction in Transaction,
        where: transaction.from_address_hash == ^address_hash
      )

    Repo.aggregate(to_address_query, :sum, :gas_used, timeout: :infinity)
  end

  def address_to_token_transfer_count_query(address_hash) do
    from(
      token_transfer in TokenTransfer,
      where: token_transfer.to_address_hash == ^address_hash,
      or_where: token_transfer.from_address_hash == ^address_hash
    )
  end

  @spec address_to_token_transfer_count(Address.t()) :: non_neg_integer()
  def address_to_token_transfer_count(address) do
    query = address_to_token_transfer_count_query(address.hash)

    Repo.aggregate(query, :count, timeout: :infinity)
  end

  def address_hash_to_token_balances_query(address_hash) do
    from(
      tb in CurrentTokenBalance,
      where: tb.address_hash == ^address_hash,
      where: tb.value > 0
    )
  end

  @doc """
    Calculates the total gas usage for a given address.

    This function determines the appropriate gas usage calculation based on the
    address type:

    - For smart contracts (excluding EOAs with code), it first checks the gas
      usage of incoming transactions. If there are no incoming transactions or
      their gas usage is zero, it falls back to the gas usage of outgoing
      transactions.
    - For regular addresses and EOAs with code, it calculates the gas usage of
      outgoing transactions.

    ## Parameters
    - `address`: The address to calculate gas usage for.

    ## Returns
    - The total gas usage for the address.
    - `nil` if no relevant transactions are found or if the sum is null.
  """
  @spec address_to_gas_usage_count(Address.t()) :: Decimal.t() | nil
  def address_to_gas_usage_count(address) do
    if Address.smart_contract?(address) and not Address.eoa_with_code?(address) do
      incoming_transaction_gas_usage = address_to_incoming_transaction_gas_usage(address.hash)

      cond do
        !incoming_transaction_gas_usage ->
          address_to_outcoming_transaction_gas_usage(address.hash)

        Decimal.compare(incoming_transaction_gas_usage, 0) == :eq ->
          address_to_outcoming_transaction_gas_usage(address.hash)

        true ->
          incoming_transaction_gas_usage
      end
    else
      address_to_outcoming_transaction_gas_usage(address.hash)
    end
  end

  defp address_hash_to_internal_transactions_limited_count_query(address_hash) do
    query_to_address_hash_wrapped =
      InternalTransaction
      |> InternalTransaction.where_nonpending_block()
      |> InternalTransaction.where_address_fields_match(address_hash, :to_address_hash)
      |> InternalTransaction.where_is_different_from_parent_transaction()
      |> limit(@counters_limit)
      |> wrapped_union_subquery()

    query_from_address_hash_wrapped =
      InternalTransaction
      |> InternalTransaction.where_nonpending_block()
      |> InternalTransaction.where_address_fields_match(address_hash, :from_address_hash)
      |> InternalTransaction.where_is_different_from_parent_transaction()
      |> limit(@counters_limit)
      |> wrapped_union_subquery()

    query_created_contract_address_hash_wrapped =
      InternalTransaction
      |> InternalTransaction.where_nonpending_block()
      |> InternalTransaction.where_address_fields_match(address_hash, :created_contract_address_hash)
      |> InternalTransaction.where_is_different_from_parent_transaction()
      |> limit(@counters_limit)
      |> wrapped_union_subquery()

    query_to_address_hash_wrapped
    |> union(^query_from_address_hash_wrapped)
    |> union(^query_created_contract_address_hash_wrapped)
    |> wrapped_union_subquery()
    |> InternalTransaction.where_is_different_from_parent_transaction()
    |> limit(@counters_limit)
  end

  def address_counters(address, options \\ []) do
    validation_count_task =
      Task.async(fn ->
        address_to_validation_count(address.hash, options)
      end)

    Task.start_link(fn ->
      transaction_count(address)
    end)

    Task.start_link(fn ->
      token_transfers_count(address)
    end)

    Task.start_link(fn ->
      gas_usage_count(address)
    end)

    [
      validation_count_task
    ]
    |> Task.yield_many(:infinity)
    |> Enum.map(fn {_task, res} ->
      case res do
        {:ok, result} ->
          result

        {:exit, reason} ->
          raise "Query fetching address counters terminated: #{inspect(reason)}"

        nil ->
          raise "Query fetching address counters timed out."
      end
    end)
    |> List.to_tuple()
  end

  def transaction_count(address) do
    AddressTransactionsCounter.fetch(address)
  end

  def token_transfers_count(address) do
    AddressTokenTransfersCounter.fetch(address)
  end

  def gas_usage_count(address) do
    AddressTransactionsGasUsageCounter.fetch(address)
  end

  @spec address_limited_counters(Hash.t(), Keyword.t()) :: %{atom() => counter}
  def address_limited_counters(address_hash, options) do
    cached_counters =
      Enum.reduce(@types, %{}, fn type, acc ->
        case AddressesTabsCounters.get_counter(type, address_hash) do
          {_datetime, counter, status} ->
            Map.put(acc, type, {status, counter})

          _ ->
            acc
        end
      end)

    start = System.monotonic_time()

    validations_count_task =
      configure_task(
        :validations,
        cached_counters,
        address_hash_to_validated_blocks_query(address_hash),
        address_hash,
        options
      )

    transactions_from_count_task =
      run_or_ignore(cached_counters[:transactions], :transactions_from, address_hash, fn ->
        result =
          Transaction
          |> where([t], t.from_address_hash == ^address_hash)
          |> Transaction.not_dropped_or_replaced_transactions()
          |> select([t], t.hash)
          |> limit(@counters_limit)
          |> select_repo(options).all()

        stop = System.monotonic_time()
        diff = System.convert_time_unit(stop - start, :native, :millisecond)

        Logger.info("Time consumed for transactions_from_count_task for #{address_hash} is #{diff}ms")

        AddressesTabsCounters.save_transactions_counter_progress(address_hash, %{
          transactions_types: [:transactions_from],
          transactions_from: result
        })

        AddressesTabsCounters.drop_task(:transactions_from, address_hash)

        {:transactions_from, result}
      end)

    transactions_to_count_task =
      run_or_ignore(cached_counters[:transactions], :transactions_to, address_hash, fn ->
        result =
          Transaction
          |> where([t], t.to_address_hash == ^address_hash)
          |> Transaction.not_dropped_or_replaced_transactions()
          |> select([t], t.hash)
          |> limit(@counters_limit)
          |> select_repo(options).all()

        stop = System.monotonic_time()
        diff = System.convert_time_unit(stop - start, :native, :millisecond)

        Logger.info("Time consumed for transactions_to_count_task for #{address_hash} is #{diff}ms")

        AddressesTabsCounters.save_transactions_counter_progress(address_hash, %{
          transactions_types: [:transactions_to],
          transactions_to: result
        })

        AddressesTabsCounters.drop_task(:transactions_to, address_hash)

        {:transactions_to, result}
      end)

    transactions_created_contract_count_task =
      run_or_ignore(cached_counters[:transactions], :transactions_contract, address_hash, fn ->
        result =
          Transaction
          |> where([t], t.created_contract_address_hash == ^address_hash)
          |> Transaction.not_dropped_or_replaced_transactions()
          |> select([t], t.hash)
          |> limit(@counters_limit)
          |> select_repo(options).all()

        stop = System.monotonic_time()
        diff = System.convert_time_unit(stop - start, :native, :millisecond)

        Logger.info("Time consumed for transactions_created_contract_count_task for #{address_hash} is #{diff}ms")

        AddressesTabsCounters.save_transactions_counter_progress(address_hash, %{
          transactions_types: [:transactions_contract],
          transactions_contract: result
        })

        AddressesTabsCounters.drop_task(:transactions_contract, address_hash)

        {:transactions_contract, result}
      end)

    token_transfers_count_task =
      configure_task(
        :token_transfers,
        cached_counters,
        address_to_token_transfer_count_query(address_hash),
        address_hash,
        options
      )

    token_balances_count_task =
      configure_task(
        :token_balances,
        cached_counters,
        address_hash_to_token_balances_query(address_hash),
        address_hash,
        options
      )

    logs_count_task =
      configure_task(
        :logs,
        cached_counters,
        address_hash_to_logs_query(address_hash),
        address_hash,
        options
      )

    withdrawals_count_task =
      configure_task(
        :withdrawals,
        cached_counters,
        Withdrawal.address_hash_to_withdrawals_unordered_query(address_hash),
        address_hash,
        options
      )

    internal_transactions_count_task =
      configure_task(
        :internal_transactions,
        cached_counters,
        address_hash_to_internal_transactions_limited_count_query(address_hash),
        address_hash,
        options
      )

    celo_election_rewards_count_task =
      if Application.get_env(:explorer, :chain_type) == :celo do
        configure_task(
          :celo_election_rewards,
          cached_counters,
          CeloElectionReward.address_hash_to_rewards_query(address_hash),
          address_hash,
          options
        )
      else
        nil
      end

    map =
      [
        validations_count_task,
        transactions_from_count_task,
        transactions_to_count_task,
        transactions_created_contract_count_task,
        token_transfers_count_task,
        token_balances_count_task,
        logs_count_task,
        withdrawals_count_task,
        internal_transactions_count_task,
        celo_election_rewards_count_task
      ]
      |> Enum.reject(&is_nil/1)
      |> Task.yield_many(:timer.seconds(1))
      |> Enum.reduce(
        Map.merge(prepare_cache_values(cached_counters), %{transactions_types: [], transactions_hashes: []}),
        fn {task, res}, acc ->
          case res do
            {:ok, {transactions_type, transactions_hashes}} when transactions_type in @transactions_types ->
              acc
              |> (&Map.put(&1, :transactions_types, [transactions_type | &1[:transactions_types]])).()
              |> (&Map.put(&1, :transactions_hashes, &1[:transactions_hashes] ++ transactions_hashes)).()

            {:ok, {type, counter}} ->
              Map.put(acc, type, counter)

            {:exit, reason} ->
              Logger.warning(fn ->
                [
                  "Query fetching address counters for #{address_hash} terminated: #{inspect(reason)}"
                ]
              end)

              acc

            nil ->
              Logger.warning(fn ->
                [
                  "Query fetching address counters for #{address_hash} timed out."
                ]
              end)

              Task.ignore(task)

              acc
          end
        end
      )
      |> process_transactions_counter()

    map
  end

  defp run_or_ignore({ok, _counter}, _type, _address_hash, _fun) when ok in [:up_to_date, :limit_value], do: nil

  defp run_or_ignore(_, type, address_hash, fun) do
    if !AddressesTabsCounters.get_task(type, address_hash) do
      AddressesTabsCounters.set_task(type, address_hash)

      Task.async(fun)
    end
  end

  defp configure_task(counter_type, cache, query, address_hash, options) do
    address_hash = to_string(address_hash)
    start = System.monotonic_time()

    run_or_ignore(cache[counter_type], counter_type, address_hash, fn ->
      result =
        query
        |> limit(@counters_limit)
        |> select_repo(options).aggregate(:count)

      stop = System.monotonic_time()
      diff = System.convert_time_unit(stop - start, :native, :millisecond)

      Logger.info("Time consumed for #{counter_type} counter task for #{address_hash} is #{diff}ms")

      AddressesTabsCounters.set_counter(counter_type, address_hash, result)
      AddressesTabsCounters.drop_task(counter_type, address_hash)

      {counter_type, result}
    end)
  end

  defp process_transactions_counter(
         %{transactions_types: [_ | _] = transactions_types, transactions_hashes: hashes} = map
       ) do
    counter = hashes |> Enum.uniq() |> Enum.count() |> min(@counters_limit)

    if Enum.count(transactions_types) == 3 || counter == @counters_limit do
      map |> Map.put(:transactions, counter)
    else
      map
    end
  end

  defp process_transactions_counter(map), do: map

  defp prepare_cache_values(cached_counters) do
    Enum.reduce(cached_counters, %{}, fn
      {k, {_, counter}}, acc ->
        Map.put(acc, k, counter)

      {k, v}, acc ->
        Map.put(acc, k, v)
    end)
  end

  @doc """
    Returns all possible transactions type
  """
  @spec transactions_types :: list(atom)
  def transactions_types, do: @transactions_types

  @doc """
    Returns max counter value
  """
  @spec counters_limit :: integer()
  def counters_limit, do: @counters_limit
end
