defmodule Micelio.AccountsTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Accounts.{Account, OAuthIdentity, Organization, User, Token}

  describe "Account user_changeset" do
    setup do
      {:ok, user} = Repo.insert(%User{email: "changeset-test@example.com"})
      {:ok, user: user}
    end

    test "validates required fields", %{user: _user} do
      changeset = Account.user_changeset(%Account{}, %{})
      assert "can't be blank" in errors_on(changeset).handle
      assert "can't be blank" in errors_on(changeset).user_id
    end

    test "validates single character handle is valid", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "a"})
      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle maximum length", %{user: user} do
      long_handle = String.duplicate("a", 40)
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: long_handle})
      assert "should be at most 39 character(s)" in errors_on(changeset).handle
    end

    test "validates handle format - no special characters", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "test_user"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - can contain hyphens in middle", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "test-user"})
      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle format - cannot end with hyphen", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "testuser-"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot have consecutive hyphens", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "test--user"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot start with hyphen", %{user: user} do
      changeset = Account.user_changeset(%Account{}, %{user_id: user.id, handle: "-testuser"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end
  end

  describe "User changeset" do
    test "validates required email" do
      changeset = User.changeset(%User{}, %{})
      assert "can't be blank" in errors_on(changeset).email
    end

    test "validates email format" do
      changeset = User.changeset(%User{}, %{email: "invalid"})
      assert "must be a valid email address" in errors_on(changeset).email
    end

    test "validates email max length" do
      long_email = String.duplicate("a", 150) <> "@example.com"
      changeset = User.changeset(%User{}, %{email: long_email})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "normalizes email to lowercase" do
      changeset = User.changeset(%User{}, %{email: "TEST@EXAMPLE.COM"})
      assert Ecto.Changeset.get_change(changeset, :email) == "test@example.com"
    end
  end

  describe "User profile changeset" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("profile@example.com")
      {:ok, user: user}
    end

    test "validates bio length", %{user: user} do
      long_bio = String.duplicate("a", 161)
      changeset = User.profile_changeset(user, %{bio: long_bio})
      assert "should be at most 160 character(s)" in errors_on(changeset).bio
    end

    test "normalizes missing protocol on profile URLs", %{user: user} do
      changeset = User.profile_changeset(user, %{website_url: "example.com"})
      assert Ecto.Changeset.get_change(changeset, :website_url) == "https://example.com"
    end

    test "rejects invalid URLs", %{user: user} do
      changeset = User.profile_changeset(user, %{website_url: "http://"})
      assert "must be a valid URL" in errors_on(changeset).website_url
    end

    test "updates profile fields", %{user: user} do
      assert {:ok, updated} =
               Accounts.update_user_profile(user, %{
                 bio: "Shipping UI systems.",
                 twitter_url: "x.com/ui-builder"
               })

      assert updated.bio == "Shipping UI systems."
      assert updated.twitter_url == "https://x.com/ui-builder"
    end
  end

  describe "Token changeset" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("token-test@example.com")
      {:ok, user: user}
    end

    test "validates required fields", %{user: _user} do
      changeset = Token.changeset(%Token{}, %{})
      assert "can't be blank" in errors_on(changeset).user_id
      assert "can't be blank" in errors_on(changeset).purpose
    end

    test "automatically generates token", %{user: user} do
      changeset = Token.changeset(%Token{}, %{user_id: user.id, purpose: :login})
      assert Ecto.Changeset.get_change(changeset, :token) != nil
    end

    test "automatically sets expiration", %{user: user} do
      changeset = Token.changeset(%Token{}, %{user_id: user.id, purpose: :login})
      expires_at = Ecto.Changeset.get_change(changeset, :expires_at)
      assert expires_at != nil
      assert DateTime.after?(expires_at, DateTime.utc_now())
    end
  end

  describe "accounts" do
    test "get_account/1 returns the account" do
      {:ok, user} = Accounts.get_or_create_user_by_email("findme@example.com")
      assert Accounts.get_account(user.account.id).id == user.account.id
    end

    test "get_account_by_handle/1 returns the account" do
      {:ok, user} = Accounts.get_or_create_user_by_email("byhandle@example.com")
      assert Accounts.get_account_by_handle(user.account.handle).id == user.account.id
    end

    test "get_account_by_handle/1 is case-insensitive" do
      {:ok, user} = Accounts.get_or_create_user_by_email("mixedcase@example.com")
      handle = user.account.handle
      assert Accounts.get_account_by_handle(String.upcase(handle)).id == user.account.id
    end

    test "handle_available?/1 returns true for available handles" do
      assert Accounts.handle_available?("available-handle")
    end

    test "handle_available?/1 returns false for reserved handles" do
      refute Accounts.handle_available?("admin")
      refute Accounts.handle_available?("settings")
      refute Accounts.handle_available?("ruby")
      refute Accounts.handle_available?("micelio")
    end

    test "handle_available?/1 returns false for taken handles" do
      {:ok, user} = Accounts.get_or_create_user_by_email("taken@example.com")
      refute Accounts.handle_available?(user.account.handle)
    end

    test "create_organization/1 creates an organization with account" do
      assert {:ok, %Organization{} = org} =
               Accounts.create_organization(%{handle: "my-company", name: "My Company"})

      assert org.name == "My Company"
      assert org.account.handle == "my-company"
      assert Account.organization?(org.account)
    end

    test "create_organization/1 fails when handle is taken" do
      assert {:ok, %Organization{}} =
               Accounts.create_organization(%{handle: "taken-org", name: "Taken Org"})

      assert {:error, changeset} =
               Accounts.create_organization(%{handle: "taken-org", name: "Other Org"})

      assert "has already been taken" in errors_on(changeset).handle
    end

    test "create_organization/2 allows reserved handles when configured" do
      assert {:error, changeset} =
               Accounts.create_organization(%{handle: "github", name: "GitHub"})

      assert "is reserved" in errors_on(changeset).handle

      assert {:ok, %Organization{} = org} =
               Accounts.create_organization(%{handle: "github", name: "GitHub"},
                 allow_reserved: true
               )

      assert org.account.handle == "github"
    end

    test "create_organization_for_user/2 links membership" do
      {:ok, user} = Accounts.get_or_create_user_by_email("org-owner@example.com")

      assert {:ok, %Organization{} = org} =
               Accounts.create_organization_for_user(user, %{
                 handle: "owner-org",
                 name: "Owner Org"
               })

      assert Accounts.user_in_organization?(user, org.id)
    end

    test "list_organizations_for_user/1 returns only memberships" do
      {:ok, user} = Accounts.get_or_create_user_by_email("org-member@example.com")

      {:ok, org_one} =
        Accounts.create_organization_for_user(user, %{
          handle: "member-org-one",
          name: "Member Org One"
        })

      {:ok, _org_two} =
        Accounts.create_organization(%{handle: "not-a-member", name: "Not a Member"})

      organizations = Accounts.list_organizations_for_user(user)
      assert Enum.map(organizations, & &1.id) == [org_one.id]
    end

    test "get_organization_by_handle/1 returns the organization" do
      {:ok, org} =
        Accounts.create_organization(%{handle: "lookup-org", name: "Lookup Org"})

      assert {:ok, loaded} = Accounts.get_organization_by_handle("lookup-org")
      assert loaded.id == org.id
    end
  end

  describe "organization registration changeset" do
    test "validates required fields" do
      changeset = Accounts.change_organization_registration()
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).handle
    end

    test "validates handle format" do
      changeset =
        Accounts.change_organization_registration(%{"name" => "Example", "handle" => "bad_org"})

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end
  end

  describe "organization settings" do
    defp unique_org_handle(prefix) do
      random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
      "#{prefix}-#{random}"
    end

    test "updates LLM settings for an organization" do
      handle = unique_org_handle("llm-org")

      {:ok, organization} =
        Accounts.create_organization(%{handle: handle, name: "LLM Org"})

      organization = Repo.preload(organization, :account)

      assert {:ok, updated} =
               Accounts.update_account_settings(organization.account, %{
                 "llm_models" => ["gpt-4.1"],
                 "llm_default_model" => "gpt-4.1"
               })

      assert updated.llm_models == ["gpt-4.1"]
      assert updated.llm_default_model == "gpt-4.1"
    end

    test "rejects default LLM models outside the allowed list" do
      handle = unique_org_handle("llm-org-invalid")

      {:ok, organization} =
        Accounts.create_organization(%{handle: handle, name: "LLM Org Invalid"})

      organization = Repo.preload(organization, :account)

      assert {:error, changeset} =
               Accounts.update_account_settings(organization.account, %{
                 "llm_models" => ["gpt-4.1"],
                 "llm_default_model" => "gpt-4.1-mini"
               })

      assert "must be one of gpt-4.1" in errors_on(changeset).llm_default_model
    end
  end

  describe "users" do
    test "get_or_create_user_by_email/1 creates a new user with account" do
      assert {:ok, %User{} = user} = Accounts.get_or_create_user_by_email("new@example.com")
      assert user.email == "new@example.com"
      assert user.account != nil
      assert Account.user?(user.account)
    end

    test "get_or_create_user_by_email/1 returns existing user" do
      {:ok, user1} = Accounts.get_or_create_user_by_email("existing@example.com")
      {:ok, user2} = Accounts.get_or_create_user_by_email("existing@example.com")
      assert user1.id == user2.id
    end

    test "get_or_create_user_by_email/1 normalizes email to lowercase" do
      {:ok, user} = Accounts.get_or_create_user_by_email("UPPER@EXAMPLE.COM")
      assert user.email == "upper@example.com"
    end

    test "get_or_create_user_by_email/1 generates handle from email" do
      {:ok, user} = Accounts.get_or_create_user_by_email("john.doe@example.com")
      assert user.account.handle == "john-doe"
    end

    test "get_or_create_user_by_email/1 generates unique handle if taken" do
      {:ok, _} = Accounts.get_or_create_user_by_email("john@other.com")
      {:ok, user} = Accounts.get_or_create_user_by_email("john@example.com")
      assert user.account.handle == "john-1"
    end

    test "get_user/1 returns the user" do
      {:ok, user} = Accounts.get_or_create_user_by_email("getuser@example.com")
      assert Accounts.get_user(user.id).id == user.id
    end

    test "get_user_by_email/1 returns the user" do
      {:ok, user} = Accounts.get_or_create_user_by_email("byemail@example.com")
      assert Accounts.get_user_by_email("byemail@example.com").id == user.id
    end

    test "get_user_with_account/1 preloads account" do
      {:ok, user} = Accounts.get_or_create_user_by_email("withaccount@example.com")
      loaded = Accounts.get_user_with_account(user.id)
      assert loaded.account.handle != nil
    end
  end

  describe "authentication" do
    test "initiate_login/1 creates a login token" do
      assert {:ok, %Token{} = token} = Accounts.initiate_login("login@example.com")
      assert token.token != nil
      assert token.purpose == :login
      assert token.expires_at != nil
      assert token.used_at == nil
    end

    test "initiate_login/1 creates user if not exists" do
      assert {:ok, %Token{}} = Accounts.initiate_login("newlogin@example.com")
      assert Accounts.get_user_by_email("newlogin@example.com") != nil
    end

    test "verify_login_token/1 returns user for valid token" do
      {:ok, token} = Accounts.initiate_login("verify@example.com")
      assert {:ok, user} = Accounts.verify_login_token(token.token)
      assert user.email == "verify@example.com"
      assert user.account != nil
    end

    test "verify_login_token/1 marks token as used" do
      {:ok, token} = Accounts.initiate_login("markused@example.com")
      {:ok, _} = Accounts.verify_login_token(token.token)

      # Token should be marked as used
      updated_token = Repo.get!(Token, token.id)
      assert updated_token.used_at != nil
    end

    test "verify_login_token/1 fails for already used token" do
      {:ok, token} = Accounts.initiate_login("usedtoken@example.com")
      {:ok, _} = Accounts.verify_login_token(token.token)

      # Second attempt should fail
      assert {:error, :invalid_token} = Accounts.verify_login_token(token.token)
    end

    test "verify_login_token/1 fails for invalid token" do
      assert {:error, :invalid_token} = Accounts.verify_login_token("invalid-token")
    end

    test "verify_login_token/1 fails for expired token" do
      {:ok, token} = Accounts.initiate_login("expired@example.com")

      # Manually expire the token
      Repo.update!(Ecto.Changeset.change(token, expires_at: ~U[2020-01-01 00:00:00Z]))

      assert {:error, :invalid_token} = Accounts.verify_login_token(token.token)
    end

    test "Token.valid?/1 returns true for valid token" do
      {:ok, token} = Accounts.initiate_login("validcheck@example.com")
      assert Token.valid?(token)
    end

    test "Token.valid?/1 returns false for used token" do
      {:ok, token} = Accounts.initiate_login("usedcheck@example.com")
      used_token = %{token | used_at: DateTime.utc_now()}
      refute Token.valid?(used_token)
    end

    test "Token.valid?/1 returns false for expired token" do
      {:ok, token} = Accounts.initiate_login("expiredcheck@example.com")
      expired_token = %{token | expires_at: ~U[2020-01-01 00:00:00Z]}
      refute Token.valid?(expired_token)
    end
  end

  describe "oauth identities" do
    test "get_or_create_user_from_oauth/3 creates user and identity" do
      assert {:ok, %User{} = user} =
               Accounts.get_or_create_user_from_oauth(
                 "github",
                 "4242",
                 "octocat@example.com"
               )

      identity =
        Repo.get_by(OAuthIdentity, provider: "github", provider_user_id: "4242")

      assert identity.user_id == user.id
      assert user.account != nil
    end

    test "get_or_create_user_from_oauth/3 uses provider_user_id over email" do
      assert {:ok, %User{} = user} =
               Accounts.get_or_create_user_from_oauth(
                 "github",
                 "1010",
                 "first@example.com"
               )

      assert {:ok, %User{} = loaded} =
               Accounts.get_or_create_user_from_oauth(
                 "github",
                 "1010",
                 "different@example.com"
               )

      assert loaded.id == user.id
    end

    test "get_or_create_user_from_oauth/3 links by email when provider id is new" do
      {:ok, %User{} = existing_user} = Accounts.get_or_create_user_by_email("linked@example.com")

      assert {:ok, %User{} = linked_user} =
               Accounts.get_or_create_user_from_oauth(
                 "github",
                 "2222",
                 "linked@example.com"
               )

      identity = Repo.get_by(OAuthIdentity, provider: "github", provider_user_id: "2222")
      assert identity.user_id == existing_user.id
      assert linked_user.id == existing_user.id
    end
  end

  describe "TOTP" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("totp@example.com")
      {:ok, user: user}
    end

    test "enable_totp/3 stores secret and timestamps", %{user: user} do
      secret = Accounts.generate_totp_secret()
      code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))

      assert {:ok, updated} = Accounts.enable_totp(user, secret, code)
      assert updated.totp_enabled_at
      assert updated.totp_secret == secret
    end

    test "verify_totp_code/2 updates last used time", %{user: user} do
      secret = Accounts.generate_totp_secret()
      code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))

      {:ok, updated} = Accounts.enable_totp(user, secret, code)
      {:ok, updated} = Repo.update(Ecto.Changeset.change(updated, totp_last_used_at: nil))

      verify_code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))
      assert {:ok, verified} = Accounts.verify_totp_code(updated, verify_code)
      assert verified.totp_last_used_at
    end

    test "disable_totp/2 clears secret and timestamps", %{user: user} do
      secret = Accounts.generate_totp_secret()
      code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))

      {:ok, updated} = Accounts.enable_totp(user, secret, code)
      {:ok, updated} = Repo.update(Ecto.Changeset.change(updated, totp_last_used_at: nil))

      disable_code = NimbleTOTP.verification_code(secret, time: System.os_time(:second))
      assert {:ok, disabled} = Accounts.disable_totp(updated, disable_code)
      assert disabled.totp_secret == nil
      assert disabled.totp_enabled_at == nil
      assert disabled.totp_last_used_at == nil
    end
  end
end
