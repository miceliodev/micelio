defmodule Micelio.Storage.S3RevalidationJob do
  @moduledoc false

  alias Micelio.Storage.S3Revalidation

  def perform(_job) do
    S3Revalidation.run()
  end
end
