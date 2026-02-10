defmodule Micelio.Schema do
  @moduledoc """
  Base schema module that configures UUIDv7 for primary keys.

  Use this module instead of `Ecto.Schema` in your schemas:

      defmodule MyApp.User do
        use Micelio.Schema

        schema "users" do
          field :name, :string
          timestamps()
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key {:id, UUIDv7.Type, autogenerate: true}
      @foreign_key_type UUIDv7.Type
    end
  end
end
