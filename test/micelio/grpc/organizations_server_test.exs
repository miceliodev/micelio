defmodule Micelio.GRPC.OrganizationsServerTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.GRPC.Organizations.V1.OrganizationService.Server

  alias Micelio.GRPC.Organizations.V1.{
    GetOrganizationRequest,
    ListOrganizationsRequest,
    ListOrganizationsResponse,
    OrganizationResponse
  }

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  test "list_organizations returns organizations for user" do
    handle = unique_handle("org-list")
    email = "user-#{handle}@example.com"
    {:ok, user} = Accounts.get_or_create_user_by_email(email)

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: handle,
        name: "GRPC Org List"
      })

    response =
      Server.list_organizations(
        %ListOrganizationsRequest{user_id: user.id},
        nil
      )

    assert %ListOrganizationsResponse{} = response
    assert length(response.organizations) >= 1

    org_handles = Enum.map(response.organizations, & &1.handle)
    assert organization.account.handle in org_handles
  end

  test "list_organizations returns empty for user with no organizations" do
    handle = unique_handle("empty")
    email = "user-#{handle}@example.com"
    {:ok, user} = Accounts.get_or_create_user_by_email(email)

    response =
      Server.list_organizations(
        %ListOrganizationsRequest{user_id: user.id},
        nil
      )

    assert %ListOrganizationsResponse{organizations: []} = response
  end

  test "get_organization returns organization details for member" do
    handle = unique_handle("org-get")
    email = "user-#{handle}@example.com"
    {:ok, user} = Accounts.get_or_create_user_by_email(email)

    {:ok, organization} =
      Accounts.create_organization_for_user(user, %{
        handle: handle,
        name: "GRPC Org Get"
      })

    response =
      Server.get_organization(
        %GetOrganizationRequest{user_id: user.id, handle: organization.account.handle},
        nil
      )

    assert %OrganizationResponse{organization: org} = response
    assert org.handle == organization.account.handle
    assert org.name == "GRPC Org Get"
  end

  test "get_organization returns not found for non-existent organization" do
    handle = unique_handle("notfound")
    email = "user-#{handle}@example.com"
    {:ok, user} = Accounts.get_or_create_user_by_email(email)

    assert {:error, %GRPC.RPCError{status: 5}} =
             Server.get_organization(
               %GetOrganizationRequest{user_id: user.id, handle: "nonexistent"},
               nil
             )
  end

  test "get_organization returns error when handle is missing" do
    handle = unique_handle("nohandle")
    email = "user-#{handle}@example.com"
    {:ok, user} = Accounts.get_or_create_user_by_email(email)

    assert {:error, %GRPC.RPCError{status: 3}} =
             Server.get_organization(
               %GetOrganizationRequest{user_id: user.id, handle: ""},
               nil
             )
  end
end
