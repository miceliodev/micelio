defmodule Micelio.Authorization.Organizations do
  @moduledoc false

  alias Micelio.Authorization

  def authorize(action, actor, organization) do
    Authorization.authorize(:"organization_#{action}", actor, organization)
  end
end
