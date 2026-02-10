defmodule Micelio.Changelog.Entry do
  @moduledoc """
  A changelog entry struct for NimblePublisher.
  """

  @enforce_keys [:id, :version, :title, :body, :description, :categories, :date]
  defstruct [:id, :version, :title, :body, :description, :categories, :date, :author]

  def build(filename, attrs, body) do
    [year, month_day_id] = filename |> Path.rootname() |> Path.split() |> Enum.take(-2)
    [month, day, id] = String.split(month_day_id, "-", parts: 3)

    date = Date.from_iso8601!("#{year}-#{month}-#{day}")

    struct!(
      __MODULE__,
      [
        id: id,
        date: date,
        body: body
      ] ++ Map.to_list(attrs)
    )
  end
end
