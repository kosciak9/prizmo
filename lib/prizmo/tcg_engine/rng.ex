defmodule Prizmo.TcgEngine.Rng do
  @moduledoc false

  @algorithm :exsss
  @algorithm_name Atom.to_string(@algorithm)

  def algorithm, do: @algorithm_name

  def generate_seed do
    24
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  def normalize_seed(seed) when is_binary(seed) do
    seed = String.trim(seed)

    if seed == "" do
      {:error, :blank_rng_seed}
    else
      {:ok, seed}
    end
  end

  def normalize_seed(seed), do: {:error, {:invalid_rng_seed, seed}}

  def choice([], _seed, _context), do: {:error, :empty_random_choice}

  def choice(items, seed, context) when is_list(items) and is_binary(seed) do
    {index, _state} = :rand.uniform_s(length(items), seed_state(seed, context))

    {:ok, Enum.at(items, index - 1)}
  end

  def shuffle(items, seed, context) when is_list(items) and is_binary(seed) do
    {shuffled, _state} =
      Enum.reduce(items, {[], seed_state(seed, context)}, fn item, {acc, state} ->
        {insert_at, state} = :rand.uniform_s(length(acc) + 1, state)

        {List.insert_at(acc, insert_at - 1, item), state}
      end)

    shuffled
  end

  defp seed_state(seed, context) do
    <<a::unsigned-32, b::unsigned-32, c::unsigned-32, _rest::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({seed, context}))

    :rand.seed_s(@algorithm, {nonzero(a), nonzero(b), nonzero(c)})
  end

  defp nonzero(0), do: 1
  defp nonzero(value), do: value
end
