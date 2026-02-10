defmodule Micelio.Authorization.Projects do
  @moduledoc false

  alias Micelio.Authorization

  def authorize(action, actor, repository) do
    Authorization.authorize(:"project_#{action}", actor, repository)
  end
end
