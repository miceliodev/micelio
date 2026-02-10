defmodule Micelio.Authorization.ProjectVisibilityTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Authorization
  alias Micelio.Repositories

  setup do
    unique = System.unique_integer([:positive])

    {:ok, owner} = Accounts.get_or_create_user_by_email("project-owner-#{unique}@example.com")

    {:ok, organization} =
      Accounts.create_organization_for_user(owner, %{
        handle: "proj-org-#{unique}",
        name: "Project Org #{unique}"
      })

    {:ok, public_repository} =
      Micelio.Repositories.create_repository(%{
        handle: "public-#{unique}",
        name: "Public Project",
        organization_id: organization.id,
        visibility: "public"
      })

    {:ok, private_repository} =
      Micelio.Repositories.create_repository(%{
        handle: "private-#{unique}",
        name: "Private Project",
        organization_id: organization.id,
        visibility: "private"
      })

    {:ok, member} = Accounts.get_or_create_user_by_email("project-member-#{unique}@example.com")

    {:ok, _membership} =
      Accounts.create_organization_membership(%{
        user_id: member.id,
        organization_id: organization.id,
        role: "member"
      })

    {:ok, outsider} =
      Accounts.get_or_create_user_by_email("project-outsider-#{unique}@example.com")

    %{
      public_repository: public_repository,
      private_repository: private_repository,
      member: member,
      outsider: outsider
    }
  end

  test "allows unauthenticated reads for public projects", %{public_repository: public_repository} do
    assert :ok = Authorization.authorize(:repository_read, nil, public_repository)
  end

  test "denies unauthenticated reads for private projects", %{
    private_repository: private_repository
  } do
    assert {:error, :forbidden} =
             Authorization.authorize(:repository_read, nil, private_repository)
  end

  test "allows organization members to read private projects", %{
    private_repository: private_repository,
    member: member
  } do
    assert :ok = Authorization.authorize(:repository_read, member, private_repository)
  end

  test "denies non-members for private projects", %{
    private_repository: private_repository,
    outsider: outsider
  } do
    assert {:error, :forbidden} =
             Authorization.authorize(:repository_read, outsider, private_repository)
  end
end
