defmodule Explorer.Chain.Cache.Block do
  @moduledoc """
  Cache for block count.
  """

  import Ecto.Query,
    only: [
      from: 2
    ]

  use Explorer.Chain.MapCache,
    name: :block_count,
    key: :count,
    key: :async_task,
    global_ttl: :infinity,
    ttl_check_interval: :timer.seconds(1),
    callback: &async_task_on_deletion(&1)

  require Logger

  alias Explorer.{Chain, Repo}
  alias Explorer.Chain.Block
  alias Explorer.Chain.Cache.Helper

  @cache_key "block_count"

  @doc """
  Estimated count of `t:Explorer.Chain.Block.t/0`.

  Estimated count of consensus blocks.
  """
  @spec estimated_count() :: non_neg_integer()
  def estimated_count do
    estimated_count_from_blocks()
  end

  defp estimated_count_from_blocks do
    count = Helper.estimated_count_from("blocks")

    if is_nil(count), do: 0, else: trunc(count * 0.90)
  end

  defp handle_fallback(:count) do
    # This will get the task PID if one exists, check if it's running and launch
    # a new task if task doesn't exist or it's not running.
    # See next `handle_fallback` definition
    safe_get_async_task()

    {:return, nil}
  end

  defp handle_fallback(:async_task) do
    # If this gets called it means an async task was requested, but none exists
    # so a new one needs to be launched
    {:ok, task} =
      Task.start_link(fn ->
        try do
          result = fetch_count_consensus_block()

          params = %{
            counter_type: @cache_key,
            value: result
          }

          Chain.upsert_last_fetched_counter(params)

          set_count(%ConCache.Item{ttl: Helper.ttl(__MODULE__, "CACHE_BLOCK_COUNT_PERIOD"), value: result})
        rescue
          e ->
            Logger.debug([
              "Couldn't update block count: ",
              Exception.format(:error, e, __STACKTRACE__)
            ])
        end

        set_async_task(nil)
      end)

    {:update, task}
  end

  # By setting this as a `callback` an async task will be started each time the
  # `count` expires (unless there is one already running)
  defp async_task_on_deletion({:delete, _, :count}), do: safe_get_async_task()

  defp async_task_on_deletion(_data), do: nil

  @spec fetch_count_consensus_block() :: non_neg_integer
  defp fetch_count_consensus_block do
    query =
      from(block in Block,
        select: count(block.hash),
        where: block.consensus == true
      )

    Repo.one!(query, timeout: :infinity) || 0
  end
end
