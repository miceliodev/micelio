defmodule StreamData do
  @moduledoc false

  defstruct generator: nil

  def integer(min..max//_) when is_integer(min) and is_integer(max) do
    generator(fn -> Enum.random(min..max) end)
  end

  def list_of(%__MODULE__{} = gen, opts \\ []) do
    min_length = Keyword.get(opts, :min_length, 0)
    max_length = Keyword.get(opts, :max_length, min_length)

    generator(fn ->
      length = Enum.random(min_length..max_length)
      Enum.map(1..length, fn _ -> generate(gen) end)
    end)
  end

  def member_of(list) when is_list(list) and list != [] do
    generator(fn -> Enum.random(list) end)
  end

  def string(chars, opts \\ []) do
    min_length = Keyword.get(opts, :min_length, 0)
    max_length = Keyword.get(opts, :max_length, min_length)
    alphabet = normalize_chars(chars)

    generator(fn ->
      length = Enum.random(min_length..max_length)
      for _ <- 1..length, into: "", do: <<Enum.random(alphabet)>>
    end)
  end

  def map(%__MODULE__{} = gen, fun) when is_function(fun, 1) do
    generator(fn -> fun.(generate(gen)) end)
  end

  def bind(%__MODULE__{} = gen, fun) when is_function(fun, 1) do
    generator(fn ->
      gen
      |> generate()
      |> fun.()
      |> generate()
    end)
  end

  def generate(%__MODULE__{generator: fun}), do: fun.()

  defp generator(fun), do: %__MODULE__{generator: fun}

  defp normalize_chars(chars) do
    chars
    |> Enum.flat_map(fn
      first..last//_ -> Enum.to_list(first..last)
      char when is_integer(char) -> [char]
      other -> raise ArgumentError, "unsupported char spec: #{inspect(other)}"
    end)
  end
end

defmodule ExUnitProperties do
  @moduledoc false

  @default_trials 50

  def default_trials, do: @default_trials

  defmacro __using__(_opts) do
    quote do
      import ExUnitProperties
    end
  end

  defmacro property(description, do: block) do
    quote do
      test unquote(description), do: unquote(block)
    end
  end

  defmacro check({:all, _, bindings}, do: block) do
    assignments =
      bindings
      |> Enum.reverse()
      |> Enum.reduce(block, fn {:<-, _, [var, gen]}, acc ->
        quote do
          unquote(var) = StreamData.generate(unquote(gen))
          unquote(acc)
        end
      end)

    quote do
      Enum.each(1..ExUnitProperties.default_trials(), fn _ ->
        unquote(assignments)
      end)
    end
  end
end
