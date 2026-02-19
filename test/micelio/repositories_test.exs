defmodule Micelio.RepositoriesTest do
  use Micelio.DataCase, async: true

  alias Micelio.Accounts
  alias Micelio.Accounts.OrganizationMembership
  alias Micelio.Mic.Repository, as: MicRepository
  alias Micelio.Repo
  alias Micelio.Repositories
  alias Micelio.Repositories.Repository
  alias Micelio.Storage

  defp unique_handle(prefix) do
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{random}"
  end

  describe "Project changeset" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{
          handle: unique_handle("project-test"),
          name: "Project Test"
        })

      {:ok, organization: organization}
    end

    test "validates required fields", %{organization: _organization} do
      changeset = Repository.changeset(%Repository{}, %{})
      assert "can't be blank" in errors_on(changeset).handle
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).organization_id
    end

    test "validates single character handle is valid", %{organization: organization} do
      changeset =
        Repository.changeset(%Repository{}, %{
          organization_id: organization.id,
          handle: "a",
          name: "Test"
        })

      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle maximum length", %{organization: organization} do
      long_handle = String.duplicate("a", 101)

      changeset =
        Repository.changeset(%Repository{}, %{
          organization_id: organization.id,
          handle: long_handle,
          name: "Test"
        })

      assert "should be at most 100 character(s)" in errors_on(changeset).handle
    end

    test "validates handle format - no special characters", %{organization: organization} do
      changeset =
        Repository.changeset(%Repository{}, %{
          organization_id: organization.id,
          handle: "test_repository",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - can contain hyphens in middle", %{organization: organization} do
      changeset =
        Repository.changeset(%Repository{}, %{
          organization_id: organization.id,
          handle: "test-project",
          name: "Test"
        })

      refute Map.has_key?(errors_on(changeset), :handle)
    end

    test "validates handle format - cannot end with hyphen", %{organization: organization} do
      changeset =
        Repository.changeset(%Repository{}, %{
          organization_id: organization.id,
          handle: "testproject-",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot have consecutive hyphens",
         %{organization: organization} do
      changeset =
        Repository.changeset(%Repository{}, %{
          organization_id: organization.id,
          handle: "test--project",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates handle format - cannot start with hyphen", %{organization: organization} do
      changeset =
        Repository.changeset(%Repository{}, %{
          organization_id: organization.id,
          handle: "-testproject",
          name: "Test"
        })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "validates visibility inclusion", %{organization: organization} do
      changeset =
        Repository.changeset(%Repository{}, %{
          organization_id: organization.id,
          handle: "visible-project",
          name: "Visible Project",
          visibility: "secret"
        })

      assert "is invalid" in errors_on(changeset).visibility
    end
  end

  describe "create_repository/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "create-project", name: "Create Project"})

      {:ok, organization: organization}
    end

    test "creates a repository with valid attributes", %{organization: organization} do
      attrs = %{handle: "my-project", name: "My Project", organization_id: organization.id}
      assert {:ok, %Repository{} = repository} = Repositories.create_repository(attrs)
      assert repository.handle == "my-project"
      assert repository.name == "My Project"
      assert repository.organization_id == organization.id
      assert repository.visibility == "private"
    end

    test "creates a repository with description", %{organization: organization} do
      attrs = %{
        handle: "described-project",
        name: "Described Project",
        description: "A project with a description",
        organization_id: organization.id
      }

      assert {:ok, %Repository{} = repository} = Repositories.create_repository(attrs)
      assert repository.description == "A project with a description"
    end

    test "creates a repository with url", %{organization: organization} do
      attrs = %{
        handle: "linked-project",
        name: "Linked Project",
        url: "https://example.com/linked-project",
        organization_id: organization.id
      }

      assert {:ok, %Repository{} = repository} = Repositories.create_repository(attrs)
      assert repository.url == "https://example.com/linked-project"
    end

    test "rejects invalid url schemes", %{organization: organization} do
      changeset =
        Repository.changeset(%Repository{}, %{
          organization_id: organization.id,
          handle: "bad-url",
          name: "Bad Url",
          url: "javascript:alert(1)"
        })

      assert "must be a valid http(s) URL" in errors_on(changeset).url
    end

    test "fails with duplicate handle for same organization", %{organization: organization} do
      attrs = %{handle: "duplicate", name: "First", organization_id: organization.id}
      assert {:ok, _} = Repositories.create_repository(attrs)

      duplicate_attrs = %{handle: "duplicate", name: "Second", organization_id: organization.id}
      assert {:error, changeset} = Repositories.create_repository(duplicate_attrs)
      assert "has already been taken for this organization" in errors_on(changeset).handle
    end

    test "allows same handle for different organizations", %{organization: organization1} do
      {:ok, organization2} =
        Accounts.create_organization(%{handle: "other-org", name: "Other Org"})

      attrs1 = %{handle: "shared-handle", name: "First", organization_id: organization1.id}
      attrs2 = %{handle: "shared-handle", name: "Second", organization_id: organization2.id}

      assert {:ok, project1} = Repositories.create_repository(attrs1)
      assert {:ok, project2} = Repositories.create_repository(attrs2)

      assert project1.handle == project2.handle
      refute project1.organization_id == project2.organization_id
    end

    test "enforces project limit per organization", %{organization: organization} do
      limit =
        :micelio
        |> Application.get_env(:repository_limits, [])
        |> Keyword.get(:max_repositories_per_tenant, 25)

      assert is_integer(limit) and limit > 0

      for idx <- 1..limit do
        attrs = %{
          handle: "limit-#{idx}",
          name: "Limit #{idx}",
          organization_id: organization.id
        }

        assert {:ok, _project} = Repositories.create_repository(attrs)
      end

      extra_attrs = %{
        handle: "limit-extra",
        name: "Limit Extra",
        organization_id: organization.id
      }

      assert {:error, changeset} = Repositories.create_repository(extra_attrs)

      assert "project limit reached for this organization" in errors_on(changeset).base
    end
  end

  describe "fork_repository/3" do
    setup do
      {:ok, source_org} =
        Accounts.create_organization(%{handle: "source-org", name: "Source Org"})

      {:ok, target_org} =
        Accounts.create_organization(%{handle: "fork-org", name: "Fork Org"})

      {:ok, source} =
        Micelio.Repositories.create_repository(%{
          handle: "source-project",
          name: "Source Project",
          description: "Original description",
          url: "https://example.com/source",
          visibility: "public",
          organization_id: source_org.id
        })

      {:ok, source: source, target_org: target_org}
    end

    test "creates a fork with origin tracking and copied storage", %{
      source: source,
      target_org: target_org
    } do
      head_key = MicRepository.head_key(source.id)
      blob_hash = <<1::256>>
      blob_key = MicRepository.blob_key(source.id, blob_hash)

      assert {:ok, _} = Storage.put(head_key, "head-data")
      assert {:ok, _} = Storage.put(blob_key, "blob-data")

      assert {:ok, %Repository{} = forked} =
               Micelio.Repositories.fork_repository(source, target_org, %{
                 handle: "source-fork",
                 name: "Source Fork"
               })

      assert forked.forked_from_id == source.id
      assert forked.organization_id == target_org.id
      assert forked.handle == "source-fork"
      assert forked.name == "Source Fork"
      assert forked.description == source.description
      assert forked.url == source.url
      assert forked.visibility == source.visibility

      assert {:ok, "head-data"} = Storage.get(MicRepository.head_key(forked.id))
      assert {:ok, "blob-data"} = Storage.get(MicRepository.blob_key(forked.id, blob_hash))
    end

    test "rejects fork when project limit is reached", %{source: source, target_org: target_org} do
      limit =
        :micelio
        |> Application.get_env(:repository_limits, [])
        |> Keyword.get(:max_repositories_per_tenant, 25)

      assert is_integer(limit) and limit > 0

      for idx <- 1..limit do
        attrs = %{
          handle: "fork-limit-#{idx}",
          name: "Fork Limit #{idx}",
          organization_id: target_org.id
        }

        assert {:ok, _project} = Repositories.create_repository(attrs)
      end

      assert {:error, changeset} =
               Micelio.Repositories.fork_repository(source, target_org, %{
                 handle: "fork-over-limit",
                 name: "Fork Over Limit"
               })

      assert "project limit reached for this organization" in errors_on(changeset).base
    end

    test "returns errors when fork data is invalid", %{source: source, target_org: target_org} do
      assert {:error, changeset} =
               Micelio.Repositories.fork_repository(source, target_org, %{
                 handle: "invalid handle",
                 name: "Fork"
               })

      assert "must contain only alphanumeric characters and single hyphens, cannot start or end with a hyphen" in errors_on(
               changeset
             ).handle
    end

    test "defaults handle and name to the source project", %{
      source: source,
      target_org: target_org
    } do
      assert {:ok, %Repository{} = forked} = Repositories.fork_repository(source, target_org)

      assert forked.handle == source.handle
      assert forked.name == source.name
      assert forked.forked_from_id == source.id
    end
  end

  describe "get_repository/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "get-project", name: "Get Project"})

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "findme",
          name: "Find Me",
          organization_id: organization.id
        })

      {:ok, repository: repository}
    end

    test "returns the repository", %{repository: repository} do
      assert Repositories.get_repository(repository.id).id == repository.id
    end

    test "returns nil for non-existent id" do
      assert Repositories.get_repository(Ecto.UUID.generate()) == nil
    end
  end

  describe "get_repository_by_handle/2" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "handle-lookup", name: "Handle Lookup"})

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "by-handle",
          name: "By Handle",
          organization_id: organization.id
        })

      {:ok, organization: organization, repository: repository}
    end

    test "returns the repository", %{organization: organization, repository: repository} do
      assert Repositories.get_repository_by_handle(organization.id, "by-handle").id ==
               repository.id
    end

    test "is case-insensitive", %{organization: organization, repository: repository} do
      assert Repositories.get_repository_by_handle(organization.id, "BY-HANDLE").id ==
               repository.id
    end

    test "returns nil for non-existent handle", %{organization: organization} do
      assert Repositories.get_repository_by_handle(organization.id, "nonexistent") == nil
    end

    test "returns nil for different organization", %{repository: repository} do
      {:ok, other_org} =
        Accounts.create_organization(%{handle: "other-lookup", name: "Other Lookup"})

      assert Repositories.get_repository_by_handle(other_org.id, repository.handle) == nil
    end
  end

  describe "list_repositories_for_organization/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "list-projects", name: "List Projects"})

      {:ok, organization: organization}
    end

    test "returns empty list when no projects", %{organization: organization} do
      assert Repositories.list_repositories_for_organization(organization.id) == []
    end

    test "returns all projects for organization ordered by name", %{organization: organization} do
      {:ok, p1} =
        Micelio.Repositories.create_repository(%{
          handle: "zebra",
          name: "Zebra",
          organization_id: organization.id
        })

      {:ok, p2} =
        Micelio.Repositories.create_repository(%{
          handle: "alpha",
          name: "Alpha",
          organization_id: organization.id
        })

      {:ok, p3} =
        Micelio.Repositories.create_repository(%{
          handle: "middle",
          name: "Middle",
          organization_id: organization.id
        })

      repositories = Repositories.list_repositories_for_organization(organization.id)
      assert length(repositories) == 3
      assert Enum.map(repositories, & &1.id) == [p2.id, p3.id, p1.id]
    end

    test "does not return projects from other organizations", %{organization: organization} do
      {:ok, _} =
        Micelio.Repositories.create_repository(%{
          handle: "mine",
          name: "Mine",
          organization_id: organization.id
        })

      {:ok, other_org} =
        Accounts.create_organization(%{handle: "other-list", name: "Other List"})

      {:ok, _} =
        Micelio.Repositories.create_repository(%{
          handle: "theirs",
          name: "Theirs",
          organization_id: other_org.id
        })

      repositories = Repositories.list_repositories_for_organization(organization.id)
      assert length(repositories) == 1
      assert hd(repositories).handle == "mine"
    end
  end

  describe "list_public_repositories_for_organization/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "list-public", name: "List Public"})

      {:ok, organization: organization}
    end

    test "returns only public projects", %{organization: organization} do
      {:ok, public_repository} =
        Micelio.Repositories.create_repository(%{
          handle: "public",
          name: "Public",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, _private_repository} =
        Micelio.Repositories.create_repository(%{
          handle: "private",
          name: "Private",
          organization_id: organization.id,
          visibility: "private"
        })

      repositories = Repositories.list_public_repositories_for_organization(organization.id)
      assert Enum.map(repositories, & &1.id) == [public_repository.id]
    end
  end

  describe "list_public_repositories_for_organizations/1" do
    test "returns public projects across organizations with preloaded accounts" do
      {:ok, org_one} =
        Accounts.create_organization(%{handle: "list-org-a", name: "List Org A"})

      {:ok, org_two} =
        Accounts.create_organization(%{handle: "list-org-b", name: "List Org B"})

      {:ok, public_one} =
        Micelio.Repositories.create_repository(%{
          handle: "alpha",
          name: "Alpha",
          organization_id: org_one.id,
          visibility: "public"
        })

      {:ok, _private_one} =
        Micelio.Repositories.create_repository(%{
          handle: "private",
          name: "Private",
          organization_id: org_one.id,
          visibility: "private"
        })

      {:ok, public_two} =
        Micelio.Repositories.create_repository(%{
          handle: "beta",
          name: "Beta",
          organization_id: org_two.id,
          visibility: "public"
        })

      repositories =
        Repositories.list_public_repositories_for_organizations([org_one.id, org_two.id])

      repository_ids = Enum.map(repositories, & &1.id)

      assert repository_ids == [public_one.id, public_two.id]
      assert Enum.all?(repositories, &is_binary(&1.organization.account.handle))
    end
  end

  describe "list_repositories_for_user/1" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("projects-user@example.com")

      {:ok, org_one} =
        Accounts.create_organization_for_user(user, %{
          handle: "user-org-one",
          name: "User Org One"
        })

      {:ok, org_two} =
        Accounts.create_organization_for_user(user, %{
          handle: "user-org-two",
          name: "User Org Two"
        })

      {:ok, _} =
        Micelio.Repositories.create_repository(%{
          handle: "alpha",
          name: "Alpha",
          organization_id: org_one.id
        })

      {:ok, _} =
        Micelio.Repositories.create_repository(%{
          handle: "beta",
          name: "Beta",
          organization_id: org_two.id
        })

      {:ok, user: user, org_one: org_one, org_two: org_two}
    end

    test "returns projects scoped to memberships ordered by organization handle",
         %{user: user, org_one: org_one, org_two: org_two} do
      repositories = Repositories.list_repositories_for_user(user)
      assert Enum.count(repositories) == 2

      handles = Enum.map(repositories, & &1.organization.account.handle)
      assert handles == [org_one.account.handle, org_two.account.handle]
    end
  end

  describe "update_repository/2" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "update-project", name: "Update Project"})

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "original",
          name: "Original",
          organization_id: organization.id
        })

      {:ok, repository: repository, organization: organization}
    end

    test "updates project name", %{repository: repository} do
      assert {:ok, updated} = Repositories.update_repository(repository, %{name: "Updated Name"})
      assert updated.name == "Updated Name"
      assert updated.handle == "original"
    end

    test "updates project description", %{repository: repository} do
      assert {:ok, updated} =
               Repositories.update_repository(repository, %{description: "New description"})

      assert updated.description == "New description"
    end

    test "updates project handle", %{repository: repository} do
      assert {:ok, updated} = Repositories.update_repository(repository, %{handle: "new-handle"})
      assert updated.handle == "new-handle"
    end

    test "allows clearing project url", %{repository: repository} do
      assert {:ok, updated} =
               Repositories.update_repository(repository, %{url: "https://example.com/repo"})

      assert updated.url == "https://example.com/repo"

      assert {:ok, cleared} = Repositories.update_repository(updated, %{url: nil})
      assert cleared.url == nil
    end

    test "fails with invalid handle", %{repository: repository} do
      assert {:error, changeset} =
               Repositories.update_repository(repository, %{handle: "invalid_handle"})

      assert Map.has_key?(errors_on(changeset), :handle)
    end
  end

  describe "update_repository_settings/2" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "settings-project", name: "Settings Project"})

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "settings-llm",
          name: "Settings LLM",
          organization_id: organization.id
        })

      {:ok, repository: repository}
    end
  end

  describe "delete_repository/1" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "delete-project", name: "Delete Project"})

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "deleteme",
          name: "Delete Me",
          organization_id: organization.id
        })

      {:ok, repository: repository}
    end

    test "deletes the repository", %{repository: repository} do
      assert {:ok, _} = Repositories.delete_repository(repository)
      assert Repositories.get_repository(repository.id) == nil
    end
  end

  describe "handle_available?/2" do
    setup do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "handle-available", name: "Handle Available"})

      {:ok, _} =
        Micelio.Repositories.create_repository(%{
          handle: "taken",
          name: "Taken",
          organization_id: organization.id
        })

      {:ok, organization: organization}
    end

    test "returns true for available handles", %{organization: organization} do
      assert Repositories.handle_available?(organization.id, "available")
    end

    test "returns false for taken handles", %{organization: organization} do
      refute Repositories.handle_available?(organization.id, "taken")
    end

    test "returns false for taken handles (case-insensitive)", %{organization: organization} do
      refute Repositories.handle_available?(organization.id, "TAKEN")
    end

    test "returns true for same handle in different organization" do
      {:ok, other_org} =
        Accounts.create_organization(%{handle: "other-available", name: "Other Available"})

      assert Repositories.handle_available?(other_org.id, "taken")
    end
  end

  describe "get_repository_for_user_by_handle/3" do
    setup do
      {:ok, user} = Accounts.get_or_create_user_by_email("project-access@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{
          handle: "access-org",
          name: "Access Org"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "access-project",
          name: "Access Project",
          organization_id: organization.id
        })

      {:ok, public_repository} =
        Micelio.Repositories.create_repository(%{
          handle: "public-project",
          name: "Public Project",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok,
       user: user,
       organization: organization,
       repository: repository,
       public_repository: public_repository}
    end

    test "returns the repository for authorized user", %{
      user: user,
      organization: organization,
      repository: repository
    } do
      assert {:ok, loaded, org} =
               Micelio.Repositories.get_repository_for_user_by_handle(
                 user,
                 organization.account.handle,
                 repository.handle
               )

      assert loaded.id == repository.id
      assert org.id == organization.id
    end

    test "returns unauthorized for non-member", %{repository: repository} do
      {:ok, other_user} = Accounts.get_or_create_user_by_email("project-other@example.com")

      assert {:error, :unauthorized} =
               Micelio.Repositories.get_repository_for_user_by_handle(
                 other_user,
                 "access-org",
                 repository.handle
               )
    end

    test "returns public project for anonymous user", %{
      organization: organization,
      public_repository: public_repository
    } do
      assert {:ok, loaded, org} =
               Micelio.Repositories.get_repository_for_user_by_handle(
                 nil,
                 organization.account.handle,
                 public_repository.handle
               )

      assert loaded.id == public_repository.id
      assert org.id == organization.id
    end
  end

  describe "search_repositories/2" do
    test "returns public projects for anonymous users" do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "search-org", name: "Search Org"})

      {:ok, public_repository} =
        Micelio.Repositories.create_repository(%{
          handle: "public-repo",
          name: "Searchable Project",
          description: "Fast search for repositories",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, _private_repository} =
        Micelio.Repositories.create_repository(%{
          handle: "private-repo",
          name: "Private Searchable",
          description: "Search secrets",
          organization_id: organization.id,
          visibility: "private"
        })

      results = Repositories.search_repositories("search", user: nil)

      assert Enum.any?(results, &(&1.id == public_repository.id))
      refute Enum.any?(results, &(&1.handle == "private-repo"))
    end

    test "includes private projects for members" do
      {:ok, user} = Accounts.get_or_create_user_by_email("searcher@example.com")

      {:ok, organization} =
        Accounts.create_organization_for_user(user, %{handle: "member-org", name: "Member Org"})

      {:ok, private_repository} =
        Micelio.Repositories.create_repository(%{
          handle: "member-repo",
          name: "Secret Search",
          description: "Private search target",
          organization_id: organization.id,
          visibility: "private"
        })

      results = Repositories.search_repositories("secret", user: user)

      assert Enum.any?(results, &(&1.id == private_repository.id))
    end

    test "returns empty list for blank queries" do
      assert [] == Repositories.search_repositories("   ", user: nil)
    end

    test "matches terms in descriptions" do
      unique = System.unique_integer([:positive])

      {:ok, organization} =
        Accounts.create_organization(%{
          handle: "desc-org-#{unique}",
          name: "Description Org #{unique}"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "desc-repo-#{unique}",
          name: "Plain Project",
          description: "A nebula of repository search terms",
          organization_id: organization.id,
          visibility: "public"
        })

      results = Repositories.search_repositories("nebula", user: nil)

      assert Enum.any?(results, &(&1.id == repository.id))
    end

    test "matches terms in names when descriptions are empty" do
      unique = System.unique_integer([:positive])

      {:ok, organization} =
        Accounts.create_organization(%{
          handle: "name-org-#{unique}",
          name: "Name Org #{unique}"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "name-repo-#{unique}",
          name: "Aurora Search",
          description: nil,
          organization_id: organization.id,
          visibility: "public"
        })

      results = Repositories.search_repositories("aurora", user: nil)

      assert Enum.any?(results, &(&1.id == repository.id))
    end

    test "matches terms split across name and description" do
      unique = System.unique_integer([:positive])

      {:ok, organization} =
        Accounts.create_organization(%{
          handle: "split-org-#{unique}",
          name: "Split Org #{unique}"
        })

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "split-repo-#{unique}",
          name: "Alpha Discovery",
          description: "Beta catalog entry",
          organization_id: organization.id,
          visibility: "public"
        })

      results = Repositories.search_repositories("alpha beta", user: nil)

      assert Enum.any?(results, &(&1.id == repository.id))
    end
  end

  describe "list_popular_repositories/1" do
    test "returns public repositories ordered by most recent" do
      unique = System.unique_integer([:positive])

      {:ok, organization} =
        Accounts.create_organization(%{
          handle: "popular-org-#{unique}",
          name: "Popular Org #{unique}"
        })

      {:ok, repo_older} =
        Micelio.Repositories.create_repository(%{
          handle: "popular-older-#{unique}",
          name: "Older Repo",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, repo_newer} =
        Micelio.Repositories.create_repository(%{
          handle: "popular-newer-#{unique}",
          name: "Newer Repo",
          organization_id: organization.id,
          visibility: "public"
        })

      {:ok, _repo_private} =
        Micelio.Repositories.create_repository(%{
          handle: "popular-private-#{unique}",
          name: "Private Repo",
          organization_id: organization.id,
          visibility: "private"
        })

      results = Repositories.list_popular_repositories(limit: 10, offset: 0)
      result_ids = Enum.map(results, & &1.id)

      assert repo_newer.id in result_ids
      assert repo_older.id in result_ids
      refute Enum.any?(results, &(&1.visibility == "private"))
    end
  end

  describe "ensure_micelio_workspace/0" do
    test "creates the micelio org, membership, and project" do
      assert {:ok, %{user: user, organization: organization, repository: repository}} =
               Micelio.Repositories.ensure_micelio_workspace()

      assert user.email == "micelio@micelio.dev"
      assert organization.account.handle == "micelio"
      assert repository.handle == "micelio"
      assert repository.name == "Micelio"
      assert repository.description == "The Micelio platform"
      assert repository.url == "https://micelio.dev"
      assert repository.visibility == "public"

      assert %OrganizationMembership{} =
               Repo.get_by(OrganizationMembership,
                 user_id: user.id,
                 organization_id: organization.id
               )
    end

    test "backfills missing project metadata and is idempotent" do
      {:ok, organization} =
        Accounts.create_organization(%{handle: "micelio", name: "Micelio"},
          allow_reserved: true
        )

      {:ok, repository} =
        Micelio.Repositories.create_repository(%{
          handle: "micelio",
          name: "Micelio",
          organization_id: organization.id,
          visibility: "private"
        })

      assert repository.description == nil
      assert repository.url == nil

      assert {:ok, %{repository: updated_repository}} = Repositories.ensure_micelio_workspace()
      assert updated_repository.id == repository.id
      assert updated_repository.description == "The Micelio platform"
      assert updated_repository.url == "https://micelio.dev"
      assert updated_repository.visibility == "public"

      assert {:ok, %{repository: same_repository}} = Repositories.ensure_micelio_workspace()
      assert same_repository.id == updated_repository.id
    end
  end
end
