defmodule MicelioWeb.Browser.RepositoryController do
  use MicelioWeb, :controller

  alias Micelio.AITokens
  alias Micelio.AITokens.TokenContribution
  alias Micelio.AITokens.TokenPool
  alias Micelio.Authorization
  alias Micelio.Mic.Binary
  alias Micelio.Mic.Project, as: MicProject
  alias Micelio.Notifications
  alias Micelio.Repositories
  alias Micelio.Sessions
  alias Micelio.Sessions.Blame
  alias Micelio.Storage
  alias MicelioWeb.Badges.ProjectBadge
  alias MicelioWeb.CodeHighlighter
  alias MicelioWeb.Markdown
  alias MicelioWeb.PageMeta
  alias MicelioWeb.SchemaOrg

  def badge(conn, _params) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         :ok <- Authorization.authorize(:repository_read, conn.assigns.current_user, repository) do
      stars = Repositories.count_repository_stars(repository)
      label = "#{account.handle}/#{repository.handle}"
      message = "#{stars} stars"

      conn
      |> put_resp_content_type("image/svg+xml")
      |> put_resp_header("cache-control", "public, max-age=300")
      |> send_resp(200, ProjectBadge.render(label, message))
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def show(conn, %{"account" => account_handle, "repository" => repository_handle}) do
    render_tree(conn, account_handle, repository_handle, "")
  end

  def tree(conn, %{"account" => account_handle, "repository" => repository_handle, "path" => path}) do
    render_tree(conn, account_handle, repository_handle, Enum.join(path, "/"))
  end

  def tree(conn, %{"account" => account_handle, "repository" => repository_handle}) do
    render_tree(conn, account_handle, repository_handle, "")
  end

  def blob(conn, %{"account" => account_handle, "repository" => repository_handle, "path" => path}) do
    render_blob(conn, account_handle, repository_handle, Enum.join(path, "/"))
  end

  def blame(conn, %{
        "account" => account_handle,
        "repository" => repository_handle,
        "path" => path
      }) do
    render_blame(conn, account_handle, repository_handle, Enum.join(path, "/"))
  end

  def toggle_star(
        conn,
        %{"account" => account_handle, "repository" => repository_handle} = params
      ) do
    return_to = get_in(params, ["star", "return_to"])

    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         user when not is_nil(user) <- conn.assigns.current_user,
         :ok <- Authorization.authorize(:repository_read, user, repository) do
      if Repositories.repository_starred?(user, repository) do
        _ = Repositories.unstar_repository(user, repository)
      else
        case Micelio.Repositories.star_repository(user, repository) do
          {:ok, _star} -> _ = Notifications.dispatch_repository_starred(repository, user)
          {:error, _changeset} -> :error
        end
      end

      _ = Repositories.record_repository_interaction(user, repository, "pulse")

      redirect(conn,
        to: safe_return_path(return_to, account_handle, repository_handle)
      )
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  def contribute_tokens(
        conn,
        %{"account" => account_handle, "repository" => repository_handle} = params
      ) do
    return_to = get_in(params, ["token_contribution", "return_to"])

    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         user when not is_nil(user) <- conn.assigns.current_user,
         :ok <- Authorization.authorize(:repository_read, user, repository),
         {:ok, _contribution, _pool} <-
           AITokens.contribute_tokens(
             repository,
             user,
             Map.get(params, "token_contribution", %{})
           ) do
      conn
      |> put_flash(:info, "Thanks for contributing tokens to this repository.")
      |> redirect(to: safe_return_path(return_to, account_handle, repository_handle))
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, format_contribution_errors(changeset))
        |> redirect(to: safe_return_path(return_to, account_handle, repository_handle))

      _ ->
        send_resp(conn, 404, "Not found")
    end
  end

  defp render_tree(conn, account_handle, repository_handle, dir_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         :ok <- Authorization.authorize(:repository_read, conn.assigns.current_user, repository),
         {:ok, head} <- MicProject.get_head(repository.id) do
      head = head || %{position: 0, tree_hash: Binary.zero_hash()}

      with {:ok, tree} <- MicProject.get_tree(repository.id, head.tree_hash) do
        dir_path = String.trim(dir_path || "", "/")

        cond do
          dir_path == "" ->
            render_tree_page(
              conn,
              account_handle,
              repository_handle,
              account,
              repository,
              head,
              tree,
              dir_path
            )

          MicProject.blob_hash_for_path(tree, dir_path) ->
            redirect(conn,
              to: ~p"/#{account_handle}/#{repository_handle}/blob/#{path_segments(dir_path)}"
            )

          MicProject.directory_exists?(tree, dir_path) ->
            render_tree_page(
              conn,
              account_handle,
              repository_handle,
              account,
              repository,
              head,
              tree,
              dir_path
            )

          true ->
            send_resp(conn, 404, "Not found")
        end
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp render_tree_page(
         conn,
         account_handle,
         repository_handle,
         account,
         repository,
         head,
         tree,
         dir_path
       ) do
    entries = MicProject.list_entries(tree, dir_path)

    readme =
      if dir_path == "" do
        readme_for_root(repository.id, tree, entries)
      end

    title_parts =
      if dir_path == "" do
        ["#{account_handle}/#{repository_handle}"]
      else
        [dir_path, "#{account_handle}/#{repository_handle}"]
      end

    conn
    |> PageMeta.put(
      title_parts: title_parts,
      description: repository.description,
      canonical_url:
        if dir_path == "" do
          url(~p"/#{account_handle}/#{repository_handle}")
        else
          url(~p"/#{account_handle}/#{repository_handle}/tree/#{path_segments(dir_path)}")
        end
    )
    |> assign(:account, account)
    |> assign(:repository, repository)
    |> assign(:head, head)
    |> assign(:dir_path, dir_path)
    |> assign(:entries, entries)
    |> assign(:readme, readme)
    |> assign_star_data(repository)
    |> assign_token_pool_data(repository)
    |> maybe_assign_schema_json_ld(dir_path, account, repository)
    |> track_repository_interaction(repository, "view")
    |> render(:show)
  end

  defp render_blob(conn, account_handle, repository_handle, file_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         :ok <- Authorization.authorize(:repository_read, conn.assigns.current_user, repository),
         {:ok, head} <- MicProject.get_head(repository.id) do
      head = head || %{position: 0, tree_hash: Binary.zero_hash()}

      with {:ok, tree} <- MicProject.get_tree(repository.id, head.tree_hash) do
        file_path = String.trim(file_path || "", "/")

        with blob_hash when is_binary(blob_hash) <-
               MicProject.blob_hash_for_path(tree, file_path),
             {:ok, content} <- MicProject.get_blob(repository.id, blob_hash) do
          title_parts = [file_path, "#{account_handle}/#{repository_handle}"]
          blob_download_url = maybe_blob_cdn_url(repository, blob_hash, storage_opts(conn))

          conn
          |> PageMeta.put(
            title_parts: title_parts,
            description: repository.description,
            canonical_url:
              url(~p"/#{account_handle}/#{repository_handle}/blob/#{path_segments(file_path)}")
          )
          |> assign(:account, account)
          |> assign(:repository, repository)
          |> assign(:head, head)
          |> assign(:file_path, file_path)
          |> assign(:blob_download_url, blob_download_url)
          |> assign(:file_content, format_blob_content(file_path, content))
          |> assign_star_data(repository)
          |> track_repository_interaction(repository, "view")
          |> render(:blob)
        else
          _ -> send_resp(conn, 404, "Not found")
        end
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp render_blame(conn, account_handle, repository_handle, file_path) do
    with account when not is_nil(account) <- conn.assigns.selected_account,
         repository when not is_nil(repository) <- conn.assigns.selected_repository,
         :ok <- Authorization.authorize(:repository_read, conn.assigns.current_user, repository),
         {:ok, head} <- MicProject.get_head(repository.id) do
      head = head || %{position: 0, tree_hash: Binary.zero_hash()}

      with {:ok, tree} <- MicProject.get_tree(repository.id, head.tree_hash) do
        file_path = String.trim(file_path || "", "/")

        with blob_hash when is_binary(blob_hash) <-
               MicProject.blob_hash_for_path(tree, file_path),
             {:ok, content} <- MicProject.get_blob(repository.id, blob_hash) do
          title_parts = ["Blame", file_path, "#{account_handle}/#{repository_handle}"]
          blame_content = format_file_content(content)

          blame_lines =
            case blame_content do
              {:text, text} ->
                repository.id
                |> Sessions.list_landed_changes_for_file(file_path)
                |> then(&Blame.build_lines(text, &1))
                |> Enum.map(&format_blame_line/1)

              _ ->
                []
            end

          conn
          |> PageMeta.put(
            title_parts: title_parts,
            description: repository.description,
            canonical_url:
              url(~p"/#{account_handle}/#{repository_handle}/blame/#{path_segments(file_path)}")
          )
          |> assign(:account, account)
          |> assign(:repository, repository)
          |> assign(:head, head)
          |> assign(:file_path, file_path)
          |> assign(:blame_content, blame_content)
          |> assign(:blame_lines, blame_lines)
          |> assign_star_data(repository)
          |> track_repository_interaction(repository, "view")
          |> render(:blame)
        else
          _ -> send_resp(conn, 404, "Not found")
        end
      end
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp maybe_assign_schema_json_ld(conn, dir_path, account, repository) do
    if dir_path == "" do
      assign(conn, :schema_json_ld, repository_schema_json_ld(account, repository))
    else
      conn
    end
  end

  defp repository_schema_json_ld(account, repository) do
    repository_url = url(~p"/#{account.handle}/#{repository.handle}")
    author_url = url(~p"/#{account.handle}")

    account
    |> SchemaOrg.software_source_code(repository,
      url: repository_url,
      code_repository: repository_url,
      author_url: author_url
    )
    |> SchemaOrg.encode()
  end

  defp assign_star_data(conn, repository) do
    return_to = current_path(conn)

    conn
    |> assign(:star_form, Phoenix.Component.to_form(%{"return_to" => return_to}, as: :star))
    |> assign(:starred?, Repositories.repository_starred?(conn.assigns.current_user, repository))
    |> assign(:stars_count, Repositories.count_repository_stars(repository))
  end

  defp track_repository_interaction(conn, repository, type) do
    case conn.assigns.current_user do
      %{} = user ->
        _ = Repositories.record_repository_interaction(user, repository, type)
        conn

      _ ->
        conn
    end
  end

  defp assign_token_pool_data(conn, repository) do
    pool =
      case AITokens.get_token_pool_by_project(repository.id) do
        %TokenPool{} = pool -> pool
        nil -> %TokenPool{repository_id: repository.id, balance: 0, reserved: 0}
      end

    available = max(pool.balance - pool.reserved, 0)
    usage = AITokens.repository_usage_summary(repository)

    acceptance_rate =
      format_acceptance_rate(usage.accepted_prompt_requests, usage.total_prompt_requests)

    form =
      Phoenix.Component.to_form(
        AITokens.change_token_contribution(%TokenContribution{}, %{}),
        as: :token_contribution
      )

    conn
    |> assign(:token_pool, pool)
    |> assign(:token_pool_available, available)
    |> assign(:token_usage, usage)
    |> assign(:token_usage_acceptance_rate, acceptance_rate)
    |> assign(:token_return_to, current_path(conn))
    |> assign(:token_contribution_form, form)
  end

  defp format_acceptance_rate(accepted, total) when is_integer(accepted) and is_integer(total) do
    if total > 0 do
      rate = accepted / total * 100
      "#{:erlang.float_to_binary(rate, decimals: 1)}%"
    else
      "n/a"
    end
  end

  defp safe_return_path(return_to, account_handle, repository_handle) do
    if is_binary(return_to) and String.starts_with?(return_to, "/") do
      return_to
    else
      ~p"/#{account_handle}/#{repository_handle}"
    end
  end

  defp format_contribution_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} ->
      "#{field} #{Enum.join(errors, ", ")}"
    end)
  end

  defp format_file_content(content) when is_binary(content) do
    limit = 200_000
    content = if byte_size(content) > limit, do: binary_part(content, 0, limit), else: content

    if String.valid?(content) do
      {:text, content}
    else
      {:binary, byte_size(content)}
    end
  end

  defp format_blob_content(file_path, content) when is_binary(content) do
    limit = 200_000
    content = if byte_size(content) > limit, do: binary_part(content, 0, limit), else: content

    if String.valid?(content) do
      case CodeHighlighter.highlight(file_path, content) do
        {:ok, highlighted} -> {:highlighted, highlighted}
        :no_lexer -> {:text, content}
      end
    else
      {:binary, byte_size(content)}
    end
  end

  defp maybe_blob_cdn_url(%{visibility: "public", id: repository_id}, blob_hash, opts) do
    repository_id
    |> MicProject.blob_key(blob_hash)
    |> Storage.cdn_url(opts)
  end

  defp maybe_blob_cdn_url(_project, _blob_hash, _opts), do: nil

  defp storage_opts(conn) do
    case conn.assigns[:storage_config] do
      nil -> []
      config -> [storage_config: config]
    end
  end

  @readme_candidates ["readme.md", "readme.markdown", "readme.mdown", "readme.txt", "readme"]
  @readme_markdown_extensions [".md", ".markdown", ".mdown"]

  defp readme_for_root(repository_id, tree, entries) do
    case find_readme_entry(entries) do
      nil ->
        nil

      entry ->
        with blob_hash when is_binary(blob_hash) <-
               MicProject.blob_hash_for_path(tree, entry.path),
             {:ok, content} <- MicProject.get_blob(repository_id, blob_hash) do
          %{path: entry.path, content: format_readme_content(entry.path, content)}
        else
          _ -> nil
        end
    end
  end

  defp find_readme_entry(entries) do
    Enum.find_value(@readme_candidates, fn candidate ->
      Enum.find(entries, fn entry ->
        entry.type == :blob and String.downcase(entry.name) == candidate
      end)
    end)
  end

  defp format_readme_content(path, content) when is_binary(path) and is_binary(content) do
    case format_file_content(content) do
      {:text, text} ->
        if markdown_readme?(path) do
          case Markdown.render(text) do
            {:ok, html} -> {:html, html}
            {:error, html} when is_binary(html) and html != "" -> {:html, html}
            {:error, _} -> {:text, text}
          end
        else
          {:text, text}
        end

      other ->
        other
    end
  end

  defp markdown_readme?(path) do
    path
    |> Path.extname()
    |> String.downcase()
    |> Kernel.in(@readme_markdown_extensions)
  end

  defp format_blame_line(%{attribution: attribution} = line) do
    session = if attribution, do: Map.get(attribution, :session)
    account = if session, do: session.user && session.user.account

    %{
      line_number: line.line_number,
      text: line.text,
      author_handle: if(account, do: account.handle),
      session_id: if(session, do: session.session_id),
      landed_at: format_blame_date(session && session.landed_at)
    }
  end

  defp path_segments(path) when is_binary(path) do
    String.split(path, "/", trim: true)
  end

  defp format_blame_date(nil), do: "unknown"
  defp format_blame_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")
end
