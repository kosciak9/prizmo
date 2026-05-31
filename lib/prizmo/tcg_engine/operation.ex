defmodule Prizmo.TcgEngine.Operation do
  @moduledoc false

  alias Prizmo.Repo

  @notifications_key {__MODULE__, :notifications}

  def transaction(fun) when is_function(fun, 0) do
    Process.put(@notifications_key, [])

    result =
      Repo.transaction(fn ->
        case fun.() do
          {:ok, value} -> value
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    notifications = Process.delete(@notifications_key) || []

    case result do
      {:ok, _value} ->
        notifications
        |> Enum.reverse()
        |> List.flatten()
        |> Ash.Notifier.notify()

        result

      {:error, _reason} ->
        result
    end
  end

  def create(resource, action, attrs) do
    resource
    |> Ash.Changeset.for_create(action, attrs)
    |> Ash.create(return_notifications?: true)
    |> unpack_write_result()
  end

  def update(record, action, attrs) do
    record
    |> Ash.Changeset.for_update(action, attrs)
    |> Ash.update(return_notifications?: true)
    |> unpack_write_result()
  end

  def bulk_destroy(query, action, input \\ %{}) do
    query
    |> Ash.bulk_destroy(action, input, return_notifications?: true)
    |> unpack_bulk_destroy_result()
  end

  defp unpack_write_result({:ok, value, notifications}) do
    Process.put(@notifications_key, [notifications | Process.get(@notifications_key, [])])
    {:ok, value}
  end

  defp unpack_write_result({:error, reason}), do: {:error, reason}

  defp unpack_bulk_destroy_result(%Ash.BulkResult{status: :success, notifications: notifications}) do
    Process.put(@notifications_key, [
      List.wrap(notifications) | Process.get(@notifications_key, [])
    ])

    {:ok, :destroyed}
  end

  defp unpack_bulk_destroy_result(%Ash.BulkResult{errors: errors}) do
    {:error, errors}
  end
end
