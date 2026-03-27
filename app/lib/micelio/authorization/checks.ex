defmodule Micelio.Authorization.Checks do
  @moduledoc false

  alias Micelio.Accounts
  alias Micelio.Accounts.{Account, Organization, User}
  alias Micelio.Repositories.Repository

  def authenticated_as_user(%User{}, _resource), do: true
  def authenticated_as_user(_, _resource), do: false

  def organization_member(%User{} = user, %Organization{id: organization_id}),
    do: Accounts.user_in_organization?(user, organization_id)

  def organization_member(%User{} = user, %Repository{organization_id: organization_id}),
    do: Accounts.user_in_organization?(user, organization_id)

  def organization_member(%User{} = user, organization_id) when is_binary(organization_id),
    do: Accounts.user_in_organization?(user, organization_id)

  def organization_member(_, _), do: false

  def organization_admin(%User{} = user, %Organization{id: organization_id}),
    do: Accounts.user_role_in_organization?(user, organization_id, :admin)

  def organization_admin(%User{} = user, %Repository{organization_id: organization_id}),
    do: Accounts.user_role_in_organization?(user, organization_id, :admin)

  def organization_admin(%User{} = user, organization_id) when is_binary(organization_id),
    do: Accounts.user_role_in_organization?(user, organization_id, :admin)

  def organization_admin(_, _), do: false

  def repository_public(_actor, %Repository{visibility: "public"}), do: true
  def repository_public(_, _), do: false

  def repository_member(%User{} = user, %Account{} = account),
    do: Accounts.user_has_account_access?(user, account)

  def repository_member(%User{} = user, %{account: %Account{} = account}),
    do: Accounts.user_has_account_access?(user, account)

  def repository_member(%User{} = user, %{organization_id: organization_id}),
    do: Accounts.user_in_organization?(user, organization_id)

  def repository_member(_, _), do: false

  def repository_admin(%User{} = user, %Account{} = account),
    do:
      Accounts.user_owns_account?(user, account) or
        Accounts.user_role_in_organization?(user, account.organization_id, :admin)

  def repository_admin(%User{} = user, %{account: %Account{} = account}),
    do: repository_admin(user, account)

  def repository_admin(%User{} = user, %{organization_id: organization_id}),
    do: Accounts.user_role_in_organization?(user, organization_id, :admin)

  def repository_admin(_, _), do: false
end
