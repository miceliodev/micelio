defmodule Micelio.Accounts do
  @moduledoc """
  The Accounts context handles user registration, authentication, and account management.
  """

  import Ecto.Query

  alias Micelio.Accounts.{
    Account,
    OAuthIdentity,
    Organization,
    OrganizationMembership,
    OrganizationRegistration,
    Passkey,
    User,
    Token
  }

  alias Micelio.Repo

  @doc """
  Gets an account by ID.
  """
  def get_account(id), do: Repo.get(Account, id)

  @doc """
  Gets an account by organization ID.
  """
  def get_account_by_organization_id(organization_id) do
    case Repo.get_by(Account, organization_id: organization_id) do
      nil -> {:error, :not_found}
      account -> {:ok, account}
    end
  end

  @doc """
  Gets an account by handle (case-insensitive).
  """
  def get_account_by_handle(handle) do
    Account
    |> where([a], fragment("lower(?)", a.handle) == ^String.downcase(handle))
    |> Repo.one()
  end

  @doc """
  Gets an organization by handle (case-insensitive).
  """
  def get_organization_by_handle(handle) do
    Account
    |> where([a], fragment("lower(?)", a.handle) == ^String.downcase(handle))
    |> preload(:organization)
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      %Account{organization: %Organization{} = organization} = account ->
        {:ok, %{organization | account: account}}

      %Account{} ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets an organization by ID.
  """
  def get_organization(id), do: Repo.get(Organization, id)

  @doc """
  Creates a new account for a user.
  """
  def create_user_account(attrs, opts \\ []) do
    %Account{}
    |> Account.user_changeset(attrs, opts)
    |> Repo.insert()
  end

  @doc """
  Creates a new account for an organization.
  """
  def create_organization_account(attrs, opts \\ []) do
    %Account{}
    |> Account.organization_changeset(attrs, opts)
    |> Repo.insert()
  end

  @doc """
  Creates a membership linking a user to an organization.
  """
  def create_organization_membership(attrs) do
    %OrganizationMembership{}
    |> OrganizationMembership.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Checks if a handle is available.
  """
  def handle_available?(handle) do
    normalized = String.downcase(handle)

    normalized not in Micelio.Handles.reserved() and
      is_nil(get_account_by_handle(handle))
  end

  @doc """
  Checks if a user owns an account.
  """
  def user_owns_account?(%User{} = user, %Account{user_id: user_id}) do
    user.id == user_id
  end

  def user_owns_account?(_, _), do: false

  @doc """
  Checks if a user has access to an account.
  """
  def user_has_account_access?(%User{} = user, %Account{organization_id: organization_id})
      when is_binary(organization_id) do
    user_in_organization?(user, organization_id)
  end

  def user_has_account_access?(%User{} = user, %Account{user_id: user_id}) do
    user.id == user_id
  end

  def user_has_account_access?(_, _), do: false

  @doc """
  Gets a user by ID.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a user by ID with their account preloaded.
  """
  def get_user_with_account(id) do
    User
    |> Repo.get(id)
    |> Repo.preload(:account)
  end

  @doc """
  Returns a changeset for editing a user's public profile.
  """
  def change_user_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates a user's public profile fields.
  """
  def update_user_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Lists organizations for a user.
  """
  def list_organizations_for_user(%User{} = user), do: list_organizations_for_user(user.id)

  def list_organizations_for_user(user_id) do
    Organization
    |> join(:inner, [o], m in OrganizationMembership, on: m.organization_id == o.id)
    |> where([_o, m], m.user_id == ^user_id)
    |> join(:left, [o, _m], a in assoc(o, :account))
    |> preload([_o, _m, a], account: a)
    |> order_by([_o, _m, a], asc: a.handle)
    |> Repo.all()
  end

  @doc """
  Lists organizations for a user with member counts.
  """
  def list_organizations_for_user_with_member_counts(%User{} = user),
    do: list_organizations_for_user_with_member_counts(user.id)

  def list_organizations_for_user_with_member_counts(user_id) do
    Organization
    |> join(:inner, [o], m in OrganizationMembership,
      on: m.organization_id == o.id and m.user_id == ^user_id
    )
    |> join(:left, [o, _m], a in assoc(o, :account))
    |> join(:left, [o, _m, _a], mc in OrganizationMembership, on: mc.organization_id == o.id)
    |> group_by([o, _m, a, _mc], [o.id, a.id])
    |> preload([_o, _m, a, _mc], account: a)
    |> select_merge([_o, _m, _a, mc], %{member_count: count(mc.id)})
    |> order_by([_o, _m, a, _mc], asc: a.handle)
    |> Repo.all()
  end

  @doc """
  Checks if a user belongs to an organization.
  """
  def user_in_organization?(%User{} = user, organization_id),
    do: user_in_organization?(user.id, organization_id)

  def user_in_organization?(user_id, organization_id) do
    OrganizationMembership
    |> where([m], m.user_id == ^user_id and m.organization_id == ^organization_id)
    |> Repo.exists?()
  end

  @doc """
  Lists users for an organization.
  """
  def list_users_for_organization(%Organization{} = organization),
    do: list_users_for_organization(organization.id)

  def list_users_for_organization(organization_id) do
    User
    |> join(:inner, [u], m in OrganizationMembership, on: m.user_id == u.id)
    |> where([_u, m], m.organization_id == ^organization_id)
    |> order_by([u, _m], asc: u.email)
    |> Repo.all()
  end

  @doc """
  Gets an organization membership for a user and organization.
  """
  def get_organization_membership(user_id, organization_id) do
    Repo.get_by(OrganizationMembership, user_id: user_id, organization_id: organization_id)
  end

  @doc """
  Checks if a user has a specific role in an organization.
  """
  def user_role_in_organization?(%User{} = user, organization_id, role) do
    user_role_in_organization?(user.id, organization_id, role)
  end

  def user_role_in_organization?(user_id, organization_id, role) when is_binary(role) do
    user_role_in_organization?(user_id, organization_id, String.to_existing_atom(role))
  end

  def user_role_in_organization?(user_id, organization_id, role) when is_atom(role) do
    case get_organization_membership(user_id, organization_id) do
      %OrganizationMembership{role: ^role} -> true
      _ -> false
    end
  end

  @doc """
  Lists organizations for a user with a specific role.
  """
  def list_organizations_for_user_with_role(%User{} = user, role),
    do: list_organizations_for_user_with_role(user.id, role)

  def list_organizations_for_user_with_role(user_id, role) when is_atom(role) do
    list_organizations_for_user_with_role(user_id, Atom.to_string(role))
  end

  def list_organizations_for_user_with_role(user_id, role) when is_binary(role) do
    Organization
    |> join(:inner, [o], m in OrganizationMembership, on: m.organization_id == o.id)
    |> where([_o, m], m.user_id == ^user_id and m.role == ^role)
    |> join(:left, [o, _m], a in assoc(o, :account))
    |> preload([_o, _m, a], account: a)
    |> order_by([_o, _m, a], asc: a.handle)
    |> Repo.all()
  end

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  @doc """
  Gets an OAuth identity by provider and provider user ID.
  """
  def get_oauth_identity(provider, provider_user_id)
      when is_binary(provider) and is_binary(provider_user_id) do
    Repo.get_by(OAuthIdentity, provider: provider, provider_user_id: provider_user_id)
  end

  @doc """
  Gets an OAuth identity for a user by provider.
  """
  def get_oauth_identity_for_user(%User{} = user, provider) when is_atom(provider) do
    Repo.get_by(OAuthIdentity, user_id: user.id, provider: provider)
  end

  @doc """
  Lists passkeys for a user.
  """
  def list_passkeys_for_user(%User{} = user) do
    Passkey
    |> where([p], p.user_id == ^user.id)
    |> order_by([p], desc: p.inserted_at)
    |> Repo.all()
  end

  @doc """
  Gets a passkey by ID.
  """
  def get_passkey(id), do: Repo.get(Passkey, id)

  @doc """
  Gets a passkey by credential ID.
  """
  def get_passkey_by_credential_id(credential_id) when is_binary(credential_id) do
    Repo.get_by(Passkey, credential_id: credential_id)
  end

  @doc """
  Creates a passkey for a user.
  """
  def create_passkey(%User{} = user, attrs) do
    attrs = Map.put(attrs, :user_id, user.id)

    %Passkey{}
    |> Passkey.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates passkey usage metadata.
  """
  def update_passkey_usage(%Passkey{} = passkey, attrs) do
    passkey
    |> Passkey.usage_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a passkey.
  """
  def delete_passkey(%Passkey{} = passkey) do
    Repo.delete(passkey)
  end

  @doc """
  Generates a new TOTP secret for a user.
  """
  def generate_totp_secret do
    NimbleTOTP.secret()
  end

  @doc """
  Returns true if a user has TOTP enabled.
  """
  def totp_enabled?(%User{totp_secret: secret, totp_enabled_at: enabled_at})
      when is_binary(secret) and byte_size(secret) > 0 and not is_nil(enabled_at), do: true

  def totp_enabled?(_), do: false

  @doc """
  Enables TOTP for a user after validating the setup code.
  """
  def enable_totp(%User{} = user, secret, code) when is_binary(code) and is_binary(secret) do
    cond do
      totp_enabled?(user) ->
        {:error, :already_enabled}

      valid_totp_code?(secret, code, nil) ->
        now = totp_now()

        user
        |> Ecto.Changeset.change(
          totp_secret: secret,
          totp_enabled_at: now,
          totp_last_used_at: now
        )
        |> Repo.update()

      true ->
        {:error, :invalid_code}
    end
  end

  @doc """
  Verifies a user's TOTP code and updates last used time.
  """
  def verify_totp_code(%User{} = user, code) when is_binary(code) do
    cond do
      is_nil(user.totp_secret) ->
        {:error, :not_enabled}

      valid_totp_code?(user.totp_secret, code, user.totp_last_used_at) ->
        user
        |> Ecto.Changeset.change(totp_last_used_at: totp_now())
        |> Repo.update()

      true ->
        {:error, :invalid_code}
    end
  end

  @doc """
  Disables TOTP for a user after validating the code.
  """
  def disable_totp(%User{} = user, code) when is_binary(code) do
    with {:ok, _user} <- verify_totp_code(user, code) do
      user
      |> Ecto.Changeset.change(
        totp_secret: nil,
        totp_enabled_at: nil,
        totp_last_used_at: nil
      )
      |> Repo.update()
    end
  end

  @doc """
  Gets or creates a user from an OAuth provider profile.
  """
  def get_or_create_user_from_oauth(provider, provider_user_id, email, opts \\ [])
      when is_binary(provider) and is_binary(provider_user_id) do
    access_token = Keyword.get(opts, :access_token)

    if is_binary(email) and String.trim(email) != "" do
      case get_oauth_identity(provider, provider_user_id) do
        %OAuthIdentity{} = identity ->
          identity = Repo.preload(identity, user: :account)
          # Update access token if provided
          if access_token do
            update_oauth_identity_token(identity, access_token)
          end

          {:ok, identity.user}

        nil ->
          case get_user_by_email(email) do
            %User{} = user ->
              attach_oauth_identity_to_user(user, provider, provider_user_id, access_token)

            nil ->
              create_user_for_oauth(provider, provider_user_id, email, access_token)
          end
      end
    else
      {:error, :missing_email}
    end
  end

  defp update_oauth_identity_token(identity, access_token) do
    identity
    |> OAuthIdentity.changeset(%{access_token_encrypted: access_token})
    |> Repo.update()
  end

  @doc """
  Creates a new user with an associated personal account.
  If the user with this email already exists, returns the existing user.
  """
  def get_or_create_user_by_email(email) do
    case get_user_by_email(email) do
      nil -> create_user_with_account(email)
      user -> {:ok, Repo.preload(user, :account)}
    end
  end

  defp create_user_with_account(email) do
    handle = generate_handle_from_email(email)

    Repo.transaction(fn ->
      with {:ok, user} <- create_user(%{email: email}),
           {:ok, account} <- create_user_account(%{handle: handle, user_id: user.id}) do
        %{user | account: account}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp valid_totp_code?(secret, code, since) do
    time = System.os_time(:second)

    NimbleTOTP.valid?(secret, code, time: time, since: since) or
      NimbleTOTP.valid?(secret, code, time: time - 30, since: since)
  end

  defp totp_now do
    DateTime.utc_now() |> DateTime.truncate(:second)
  end

  defp create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  defp create_user_for_oauth(provider, provider_user_id, email, access_token) do
    identity_attrs = %{
      provider: provider,
      provider_user_id: provider_user_id
    }

    identity_attrs =
      if access_token,
        do: Map.put(identity_attrs, :access_token_encrypted, access_token),
        else: identity_attrs

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.changeset(%User{}, %{email: email}))
    |> Ecto.Multi.insert(:account, fn %{user: user} ->
      Account.user_changeset(%Account{}, %{
        handle: generate_handle_from_email(email),
        user_id: user.id
      })
    end)
    |> Ecto.Multi.insert(:identity, fn %{user: user} ->
      OAuthIdentity.changeset(%OAuthIdentity{}, Map.put(identity_attrs, :user_id, user.id))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, account: account}} ->
        {:ok, %{user | account: account}}

      {:error, :identity, %Ecto.Changeset{} = changeset, _changes} ->
        case get_oauth_identity(provider, provider_user_id) do
          %OAuthIdentity{} = identity ->
            {:ok, Repo.preload(identity.user, :account)}

          nil ->
            {:error, changeset}
        end

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp attach_oauth_identity_to_user(%User{} = user, provider, provider_user_id, access_token) do
    user = Repo.preload(user, :account)

    identity_attrs = %{
      provider: provider,
      provider_user_id: provider_user_id,
      user_id: user.id
    }

    identity_attrs =
      if access_token,
        do: Map.put(identity_attrs, :access_token_encrypted, access_token),
        else: identity_attrs

    %OAuthIdentity{}
    |> OAuthIdentity.changeset(identity_attrs)
    |> Repo.insert()
    |> case do
      {:ok, _identity} ->
        {:ok, user}

      {:error, %Ecto.Changeset{} = changeset} ->
        case get_oauth_identity(provider, provider_user_id) do
          %OAuthIdentity{} = identity ->
            {:ok, Repo.preload(identity.user, :account)}

          nil ->
            {:error, changeset}
        end
    end
  end

  defp generate_handle_from_email(email) do
    base =
      email
      |> String.split("@")
      |> List.first()
      |> String.replace(~r/[^a-z0-9-]/i, "-")
      |> String.replace(~r/-+/, "-")
      |> String.trim("-")
      |> String.slice(0, 30)

    ensure_unique_handle(base)
  end

  defp ensure_unique_handle(base, suffix \\ nil) do
    handle = if suffix, do: "#{base}-#{suffix}", else: base

    if handle_available?(handle) do
      handle
    else
      new_suffix = if suffix, do: suffix + 1, else: 1
      ensure_unique_handle(base, new_suffix)
    end
  end

  @doc """
  Initiates the login flow by creating a login token for the user.
  If the user doesn't exist, creates them first.
  Returns {:ok, token} or {:error, reason}.
  """
  def initiate_login(email) do
    with {:ok, user} <- get_or_create_user_by_email(email) do
      create_login_token(user)
    end
  end

  @doc """
  Verifies a login token and returns the user if valid.
  Marks the token as used.
  """
  def verify_login_token(token_string) do
    with %Token{} = token <- get_valid_token(token_string, :login),
         {:ok, _} <- token |> Token.use_changeset() |> Repo.update() do
      {:ok, Repo.preload(token.user, :account)}
    else
      nil -> {:error, :invalid_token}
      {:error, _} -> {:error, :invalid_token}
    end
  end

  defp create_login_token(user) do
    changeset =
      %Token{}
      |> Token.changeset(%{user_id: user.id, purpose: :login})

    with {:ok, token} <- Repo.insert(changeset) do
      {:ok, Repo.preload(token, :user)}
    end
  end

  defp get_valid_token(token_string, purpose) do
    now = DateTime.utc_now()

    Token
    |> where([t], t.token == ^token_string)
    |> where([t], t.purpose == ^purpose)
    |> where([t], is_nil(t.used_at))
    |> where([t], t.expires_at > ^now)
    |> preload(:user)
    |> Repo.one()
  end

  @doc """
  Creates a new organization with an associated account.
  """
  def create_organization(attrs, opts \\ []) do
    handle = Map.get(attrs, :handle) || Map.get(attrs, "handle")
    name = Map.get(attrs, :name) || Map.get(attrs, "name")
    allow_reserved = Keyword.get(opts, :allow_reserved, false)
    org_attrs = organization_attrs(name, attrs)

    llm_models = Map.get(attrs, :llm_models) || Map.get(attrs, "llm_models")
    llm_default_model = Map.get(attrs, :llm_default_model) || Map.get(attrs, "llm_default_model")

    account_attrs =
      %{handle: handle}
      |> maybe_put(:llm_models, llm_models)
      |> maybe_put(:llm_default_model, llm_default_model)

    Repo.transaction(fn ->
      with {:ok, org} <- do_create_organization(org_attrs),
           account_attrs = Map.put(account_attrs, :organization_id, org.id),
           {:ok, account} <-
             create_organization_account(account_attrs,
               allow_reserved: allow_reserved
             ) do
        %{org | account: account}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Creates a new organization and assigns the user as an owner.
  """
  def create_organization_for_user(%User{} = user, attrs, opts \\ []) do
    handle = Map.get(attrs, :handle) || Map.get(attrs, "handle")
    name = Map.get(attrs, :name) || Map.get(attrs, "name")
    allow_reserved = Keyword.get(opts, :allow_reserved, false)
    org_attrs = organization_attrs(name, attrs)

    llm_models = Map.get(attrs, :llm_models) || Map.get(attrs, "llm_models")
    llm_default_model = Map.get(attrs, :llm_default_model) || Map.get(attrs, "llm_default_model")

    account_attrs =
      %{handle: handle}
      |> maybe_put(:llm_models, llm_models)
      |> maybe_put(:llm_default_model, llm_default_model)

    Repo.transaction(fn ->
      with {:ok, org} <- do_create_organization(org_attrs),
           account_attrs = Map.put(account_attrs, :organization_id, org.id),
           {:ok, account} <-
             create_organization_account(account_attrs,
               allow_reserved: allow_reserved
             ),
           {:ok, _membership} <-
             create_organization_membership(%{
               user_id: user.id,
               organization_id: org.id,
               role: :admin
             }) do
        %{org | account: account}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc """
  Returns a changeset for organization registration.
  """
  def change_organization_registration(attrs \\ %{}) do
    OrganizationRegistration.changeset(%OrganizationRegistration{}, attrs)
  end

  @doc """
  Returns a changeset for account settings (LLM models).
  """
  def change_account_settings(%Account{} = account, attrs \\ %{}) do
    Account.settings_changeset(account, attrs)
  end

  @doc """
  Updates account settings (LLM models).
  """
  def update_account_settings(%Account{} = account, attrs) do
    account
    |> Account.settings_changeset(attrs)
    |> Repo.update()
  end

  defp organization_attrs(name, _attrs) do
    %{name: name}
  end

  defp do_create_organization(attrs) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end
end
