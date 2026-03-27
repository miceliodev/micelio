defmodule Micelio.Accounts.OrganizationRegistration do
  @moduledoc """
  Changeset utilities for registering organizations.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :name, :string
    field :handle, :string
  end

  @doc """
  Builds a changeset for organization registration.
  """
  def changeset(%__MODULE__{} = registration, attrs) do
    registration
    |> cast(attrs, [:name, :handle])
    |> validate_required([:name, :handle])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_handle()
  end

  @doc """
  Merges errors from another changeset into the registration changeset.
  """
  def merge_errors(changeset, other_changeset) do
    Enum.reduce(other_changeset.errors, changeset, fn {field, {message, opts}}, acc ->
      opts = Enum.sort(opts)

      already_present? =
        Enum.any?(acc.errors, fn
          {^field, {^message, existing_opts}} -> Enum.sort(existing_opts) == opts
          _ -> false
        end)

      if already_present? do
        acc
      else
        add_error(acc, field, message, opts)
      end
    end)
  end

  defp validate_handle(changeset) do
    changeset
    |> validate_format(:handle, ~r/^[a-z0-9](?:[a-z0-9]|-(?=[a-z0-9])){0,38}$/i,
      message:
        "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen"
    )
    |> validate_length(:handle, min: 1, max: 39)
    |> validate_exclusion(:handle, Micelio.Handles.reserved(), message: "is reserved")
  end
end
