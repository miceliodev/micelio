defmodule Micelio.Authorization do
  @moduledoc """
  Authorization policies for Micelio resources.
  """
  use LetMe.Policy, error_reason: :forbidden

  object :organization do
    action :create do
      allow(:authenticated_as_user)
    end

    action :read do
      allow(:organization_member)
    end

    action :update do
      allow(:organization_admin)
    end

    action :delete do
      allow(:organization_admin)
    end
  end

  object :membership do
    action :read do
      allow(:organization_member)
    end

    action :create do
      allow(:organization_admin)
    end

    action :update do
      allow(:organization_admin)
    end

    action :delete do
      allow(:organization_admin)
    end
  end

  object :repository do
    action :create do
      allow(:organization_admin)
    end

    action :read do
      allow(:repository_public)
      allow(:repository_member)
    end

    action :update do
      allow(:repository_admin)
    end

    action :delete do
      allow(:organization_admin)
    end

    action :write do
      allow(:repository_admin)
    end
  end
end
