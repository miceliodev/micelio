defmodule MicelioWeb.StorageSettingsLive do
  use MicelioWeb, :live_view

  alias Micelio.Storage
  alias Micelio.Storage.S3Config
  alias MicelioWeb.PageMeta

  @region_required_providers [:aws_s3, :digitalocean_spaces, :wasabi]
  @region_optional_providers [:backblaze_b2]
  @endpoint_required_providers [
    :cloudflare_r2,
    :minio,
    :digitalocean_spaces,
    :backblaze_b2,
    :wasabi,
    :custom
  ]

  @provider_data %{
    aws_s3: %{
      label: "AWS S3",
      docs_url:
        "https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html",
      help: [
        "Create an IAM user with scoped S3 access to your bucket.",
        "Region must match the bucket's region for AWS endpoints.",
        "Endpoint is optional unless you use a custom S3-compatible host."
      ],
      endpoint_placeholder: "https://s3.us-east-1.amazonaws.com"
    },
    cloudflare_r2: %{
      label: "Cloudflare R2",
      docs_url: "https://developers.cloudflare.com/r2/api/s3/tokens/",
      help: [
        "Use your account ID in the endpoint URL, like https://<account>.r2.cloudflarestorage.com.",
        "Region is not required for R2; leave it blank.",
        "Use an API token with Object Read & Write permissions."
      ],
      endpoint_placeholder: "https://<account-id>.r2.cloudflarestorage.com"
    },
    minio: %{
      label: "MinIO",
      docs_url: "https://min.io/docs/minio/linux/administration/identity-access-management.html",
      help: [
        "Use the MinIO server URL as the endpoint (including http/https).",
        "Region is optional; use the region configured on your MinIO instance.",
        "Keys should map to the bucket policy you created."
      ],
      endpoint_placeholder: "https://minio.example.com"
    },
    digitalocean_spaces: %{
      label: "DigitalOcean Spaces",
      docs_url: "https://docs.digitalocean.com/products/spaces/how-to/manage-access/",
      help: [
        "Region must match your Space's region (for example, nyc3).",
        "Endpoint should be https://<region>.digitaloceanspaces.com.",
        "Use the Spaces access key and secret created in the control panel."
      ],
      endpoint_placeholder: "https://nyc3.digitaloceanspaces.com"
    },
    backblaze_b2: %{
      label: "Backblaze B2",
      docs_url: "https://www.backblaze.com/docs/cloud-storage-s3-compatible-api",
      help: [
        "Use the S3-compatible endpoint in your B2 bucket settings.",
        "Region is optional, but keep it in sync with the endpoint host.",
        "Use an application key with read/write/delete permissions."
      ],
      endpoint_placeholder: "https://s3.us-west-002.backblazeb2.com"
    },
    wasabi: %{
      label: "Wasabi",
      docs_url: "https://wasabi.com/docs/how-do-i-create-an-access-key-and-secret-key/",
      help: [
        "Region must match your Wasabi bucket location.",
        "Endpoint should be https://s3.<region>.wasabisys.com.",
        "Use an access key scoped to the bucket."
      ],
      endpoint_placeholder: "https://s3.us-east-1.wasabisys.com"
    },
    custom: %{
      label: "Custom",
      docs_url: "https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html",
      help: [
        "Use a fully qualified HTTPS endpoint for your S3-compatible service.",
        "Ensure your credentials have read/write/delete access to the bucket.",
        "Set a path prefix if the bucket is shared with other tools."
      ],
      endpoint_placeholder: "https://storage.example.com"
    }
  }

  @impl true
  def mount(_params, session, socket) do
    user = socket.assigns.current_user
    config = Storage.get_user_s3_config(user)
    form = Storage.change_user_s3_config(user) |> to_form(as: :s3_config)

    socket =
      socket
      |> assign(:page_title, "Storage settings")
      |> PageMeta.assign(
        description: "Configure personal S3 storage for session artifacts.",
        canonical_url: url(~p"/settings/storage")
      )
      |> assign(:s3_config, config)
      |> assign(:saved_status, saved_status(config))
      |> assign(:form, form)
      |> assign(:form_params, params_from_config(config))
      |> assign(:selected_provider, config && config.provider)
      |> assign(:test_status, :idle)
      |> assign(:test_result, nil)
      |> assign(:access_key_value, nil)
      |> assign(:secret_access_key_value, nil)
      |> assign(:show_secret, false)
      |> assign(:s3_validator, s3_validator_from_session(session))

    {:ok, socket}
  end

  @impl true
  def handle_event("validate", %{"s3_config" => params}, socket) do
    {params, provider} = normalize_params(params, socket.assigns.selected_provider)
    config = socket.assigns.s3_config || %S3Config{user_id: socket.assigns.current_user.id}

    changeset =
      config
      |> Storage.user_s3_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: :s3_config))
     |> assign(:form_params, params)
     |> assign(:selected_provider, provider)
     |> assign(:access_key_value, normalize_secret_value(params["access_key_id"]))
     |> assign(:secret_access_key_value, normalize_secret_value(params["secret_access_key"]))
     |> assign(:test_status, :idle)
     |> assign(:test_result, nil)}
  end

  @impl true
  def handle_event("save", %{"s3_config" => params}, socket) do
    user = socket.assigns.current_user
    validator = socket.assigns.s3_validator || Storage.s3_validator_module()

    case Storage.upsert_user_s3_config(user, params, validator: validator) do
      {:ok, config, {:ok, _result}} ->
        {:noreply,
         socket
         |> put_flash(:info, "Storage settings saved and validated.")
         |> assign(:s3_config, config)
         |> assign(:saved_status, saved_status(config))
         |> assign(:selected_provider, config.provider)
         |> reset_form_state(user)}

      {:ok, config, {:error, _result}} ->
        {:noreply,
         socket
         |> put_flash(:error, "Storage settings saved, but validation failed.")
         |> assign(:s3_config, config)
         |> assign(:saved_status, saved_status(config))
         |> assign(:selected_provider, config.provider)
         |> reset_form_state(user)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(Map.put(changeset, :action, :validate), as: :s3_config))
         |> assign(:test_status, :idle)
         |> assign(:test_result, nil)}
    end
  end

  @impl true
  def handle_event("test", _params, socket) do
    params = socket.assigns.form_params || %{}
    config = socket.assigns.s3_config || %S3Config{user_id: socket.assigns.current_user.id}

    changeset =
      config
      |> Storage.user_s3_changeset(params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      current_user = socket.assigns.current_user
      validator = socket.assigns.s3_validator || Storage.s3_validator_module()

      {:noreply,
       socket
       |> assign(:form, to_form(changeset, as: :s3_config))
       |> assign(:test_status, :checking)
       |> assign(:test_result, nil)
       |> start_async(:s3_test, fn ->
         Storage.validate_user_s3_config(current_user, params, validator: validator)
       end)}
    else
      {:noreply,
       socket
       |> assign(:form, to_form(changeset, as: :s3_config))
       |> assign(:test_status, :invalid)
       |> assign(:test_result, nil)}
    end
  end

  @impl true
  def handle_event("remove", _params, socket) do
    user = socket.assigns.current_user

    case Storage.delete_user_s3_config(user) do
      {:ok, _deleted} ->
        {:noreply,
         socket
         |> put_flash(:info, "Storage configuration removed.")
         |> assign(:s3_config, nil)
         |> assign(:saved_status, :none)
         |> assign(:selected_provider, nil)
         |> reset_form_state(user)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not remove storage configuration.")}
    end
  end

  @impl true
  def handle_event("toggle-secret", _params, socket) do
    {:noreply, update(socket, :show_secret, &(!&1))}
  end

  @impl true
  def handle_async(:s3_test, {:ok, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:test_status, :ok)
     |> assign(:test_result, result)}
  end

  def handle_async(:s3_test, {:ok, {:error, %Ecto.Changeset{} = changeset}}, socket) do
    {:noreply,
     socket
     |> assign(:test_status, :invalid)
     |> assign(:test_result, nil)
     |> assign(:form, to_form(Map.put(changeset, :action, :validate), as: :s3_config))}
  end

  def handle_async(:s3_test, {:ok, {:error, result}}, socket) do
    {:noreply,
     socket
     |> assign(:test_status, :error)
     |> assign(:test_result, result)}
  end

  def handle_async(:s3_test, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:test_status, :error)
     |> assign(:test_result, %{ok?: false, errors: ["Validation crashed."], steps: %{}})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
    >
      <div class="storage-settings" id="storage-settings">
        <.header>
          Storage settings
          <:subtitle>
            <p>Route session artifacts to your own S3-compatible storage.</p>
          </:subtitle>
          <:actions>
            <.link
              navigate={~p"/account"}
              class="repository-button repository-button-secondary"
              id="storage-settings-back"
            >
              Back to account
            </.link>
          </:actions>
        </.header>

        <div class="storage-settings-layout">
          <section class="storage-settings-panel" id="storage-settings-status">
            <h2 class="storage-settings-title">Connection status</h2>
            <p class="storage-settings-meta">
              {saved_status_label(@saved_status)}
              <%= if @s3_config && @s3_config.validated_at do %>
                <span class="storage-settings-muted">
                  Last checked {format_date(@s3_config.validated_at)}.
                </span>
              <% end %>
            </p>
            <%= if @s3_config && @s3_config.last_error do %>
              <p class="storage-settings-alert storage-settings-alert-error">
                {@s3_config.last_error}
              </p>
            <% end %>

            <div class="storage-settings-test" id="storage-settings-test">
              <div class="storage-settings-test-header">
                <h3 class="storage-settings-subtitle">Test connection</h3>
                <%= if @test_status == :checking do %>
                  <span class="storage-settings-spinner" aria-hidden="true"></span>
                <% end %>
              </div>

              <p class="storage-settings-test-status">
                {test_status_label(@test_status)}
              </p>

              <%= if @test_result do %>
                <%= if @test_result.ok? do %>
                  <p class="storage-settings-alert storage-settings-alert-success">
                    Connection successful.
                  </p>
                <% else %>
                  <p class="storage-settings-alert storage-settings-alert-error">
                    Connection failed.
                  </p>
                <% end %>

                <%= if Map.get(@test_result, :errors, []) != [] do %>
                  <ul class="storage-settings-errors">
                    <li :for={error <- @test_result.errors}>{error}</li>
                  </ul>
                <% end %>

                <%= if Map.get(@test_result, :steps, %{}) != %{} do %>
                  <ul class="storage-settings-steps">
                    <li :for={{step, status} <- step_entries(@test_result.steps)}>
                      <span class="storage-settings-step-label">{step_label(step)}</span>
                      <span class={step_status_class(status)}>{step_status_label(status)}</span>
                    </li>
                  </ul>
                <% end %>
              <% end %>
            </div>
          </section>

          <section class="storage-settings-panel" id="storage-settings-form-panel">
            <h2 class="storage-settings-title">S3 configuration</h2>
            <.form
              for={@form}
              id="storage-settings-form"
              phx-change="validate"
              phx-submit="save"
              class="account-profile-form"
            >
              <div class="account-profile-form-grid storage-settings-grid">
                <div class="account-profile-form-group">
                  <.input
                    field={@form[:provider]}
                    type="select"
                    label="Provider"
                    prompt="Select provider"
                    options={provider_options()}
                    class="account-profile-input"
                    error_class="account-profile-input account-profile-input-error"
                  />
                </div>
                <div class="account-profile-form-group">
                  <.input
                    field={@form[:bucket_name]}
                    type="text"
                    label="Bucket name"
                    placeholder="micelio-sessions"
                    class="account-profile-input"
                    error_class="account-profile-input account-profile-input-error"
                  />
                  <p class="account-profile-form-hint">
                    Use 3-63 lowercase letters, numbers, and hyphens.
                  </p>
                </div>

                <%= if show_region?(@selected_provider) do %>
                  <div class="account-profile-form-group">
                    <.input
                      field={@form[:region]}
                      type="select"
                      label="Region"
                      prompt="Select region"
                      options={region_options(@selected_provider)}
                      class="account-profile-input"
                      error_class="account-profile-input account-profile-input-error"
                    />
                    <p class="account-profile-form-hint">
                      <%= if region_required?(@selected_provider) do %>
                        Required for this provider.
                      <% else %>
                        Optional, but keep it aligned with your endpoint host.
                      <% end %>
                    </p>
                  </div>
                <% end %>

                <%= if show_endpoint?(@selected_provider) do %>
                  <div class="account-profile-form-group">
                    <.input
                      field={@form[:endpoint_url]}
                      type="url"
                      label="Endpoint URL"
                      placeholder={endpoint_placeholder(@selected_provider)}
                      class="account-profile-input"
                      error_class="account-profile-input account-profile-input-error"
                    />
                    <p class="account-profile-form-hint">
                      <%= if endpoint_required?(@selected_provider) do %>
                        Required for this provider.
                      <% else %>
                        Optional unless you use a custom endpoint.
                      <% end %>
                    </p>
                  </div>
                <% end %>

                <div class="account-profile-form-group">
                  <.input
                    field={@form[:access_key_id]}
                    type="text"
                    label="Access key ID"
                    placeholder="AKIA..."
                    autocomplete="off"
                    value={@access_key_value}
                    class="account-profile-input"
                    error_class="account-profile-input account-profile-input-error"
                  />
                </div>

                <div class="account-profile-form-group">
                  <label class="storage-settings-label">Secret access key</label>
                  <div class="storage-settings-secret">
                    <.input
                      field={@form[:secret_access_key]}
                      type={secret_input_type(@show_secret)}
                      placeholder="********"
                      autocomplete="new-password"
                      value={@secret_access_key_value}
                      class="account-profile-input"
                      error_class="account-profile-input account-profile-input-error"
                    />
                    <button
                      type="button"
                      class="storage-settings-toggle"
                      phx-click="toggle-secret"
                      id="storage-secret-toggle"
                    >
                      {if @show_secret, do: "Hide", else: "Show"}
                    </button>
                  </div>
                  <%= if @s3_config do %>
                    <p class="account-profile-form-hint">
                      Leave credentials blank to keep the current keys.
                    </p>
                  <% end %>
                </div>

                <div class="account-profile-form-group">
                  <.input
                    field={@form[:path_prefix]}
                    type="text"
                    label="Path prefix"
                    placeholder="micelio/"
                    class="account-profile-input"
                    error_class="account-profile-input account-profile-input-error"
                  />
                  <p class="account-profile-form-hint">
                    Optional prefix added to every object key.
                  </p>
                </div>
              </div>

              <div class="storage-settings-help">
                <h3 class="storage-settings-subtitle">Provider guidance</h3>
                <%= if provider_help(@selected_provider) != [] do %>
                  <ul class="storage-settings-help-list">
                    <li :for={line <- provider_help(@selected_provider)}>{line}</li>
                  </ul>
                <% else %>
                  <p class="storage-settings-help-empty">
                    Select a provider to see setup guidance.
                  </p>
                <% end %>
                <%= if provider_docs_url(@selected_provider) do %>
                  <a
                    href={provider_docs_url(@selected_provider)}
                    class="storage-settings-docs"
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    Read provider credential docs
                  </a>
                <% end %>
              </div>

              <div class="storage-settings-actions">
                <button
                  type="button"
                  class="repository-button repository-button-secondary"
                  id="storage-test-connection"
                  phx-click="test"
                  disabled={@test_status == :checking}
                  phx-disable-with="Testing..."
                >
                  Test connection
                </button>
                <button type="submit" class="repository-button" id="storage-settings-save">
                  Save settings
                </button>
                <%= if @s3_config do %>
                  <button
                    type="button"
                    class="repository-button repository-button-secondary storage-settings-danger"
                    id="storage-remove-configuration"
                    phx-click="remove"
                    phx-confirm="Remove this storage configuration?"
                  >
                    Remove configuration
                  </button>
                <% end %>
              </div>
            </.form>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp reset_form_state(socket, user) do
    socket
    |> assign(:form, Storage.change_user_s3_config(user) |> to_form(as: :s3_config))
    |> assign(:form_params, params_from_config(socket.assigns.s3_config))
    |> assign(:test_status, :idle)
    |> assign(:test_result, nil)
    |> assign(:access_key_value, nil)
    |> assign(:secret_access_key_value, nil)
  end

  defp saved_status(nil), do: :none
  defp saved_status(%S3Config{validated_at: %DateTime{}}), do: :validated
  defp saved_status(%S3Config{last_error: error}) when is_binary(error), do: :invalid
  defp saved_status(%S3Config{}), do: :pending

  defp saved_status_label(:validated), do: "Saved config is valid."
  defp saved_status_label(:invalid), do: "Saved config failed validation."
  defp saved_status_label(:pending), do: "Saved config validation pending."
  defp saved_status_label(:none), do: "No saved storage configuration."

  defp test_status_label(:idle), do: "No test run yet."
  defp test_status_label(:checking), do: "Testing connection..."
  defp test_status_label(:ok), do: "Latest test succeeded."
  defp test_status_label(:error), do: "Latest test failed."
  defp test_status_label(:invalid), do: "Fix validation errors before testing."

  defp provider_options do
    @provider_data
    |> Enum.map(fn {key, info} -> {info.label, Atom.to_string(key)} end)
    |> Enum.sort_by(fn {label, _value} -> label end)
  end

  defp provider_help(nil), do: []
  defp provider_help(provider), do: get_in(@provider_data, [provider, :help]) || []

  defp provider_docs_url(nil), do: nil
  defp provider_docs_url(provider), do: get_in(@provider_data, [provider, :docs_url])

  defp endpoint_placeholder(nil), do: "https://s3.example.com"

  defp endpoint_placeholder(provider) do
    get_in(@provider_data, [provider, :endpoint_placeholder]) || "https://s3.example.com"
  end

  defp show_region?(provider) when provider in @region_required_providers, do: true
  defp show_region?(provider) when provider in @region_optional_providers, do: true
  defp show_region?(_), do: false

  defp region_required?(provider) when provider in @region_required_providers, do: true
  defp region_required?(_), do: false

  defp show_endpoint?(nil), do: false
  defp show_endpoint?(_), do: true

  defp endpoint_required?(provider) when provider in @endpoint_required_providers, do: true
  defp endpoint_required?(_), do: false

  defp region_options(:aws_s3) do
    [
      {"us-east-1 (N. Virginia)", "us-east-1"},
      {"us-east-2 (Ohio)", "us-east-2"},
      {"us-west-1 (N. California)", "us-west-1"},
      {"us-west-2 (Oregon)", "us-west-2"},
      {"eu-west-1 (Ireland)", "eu-west-1"},
      {"ap-southeast-1 (Singapore)", "ap-southeast-1"}
    ]
  end

  defp region_options(:digitalocean_spaces) do
    [
      {"nyc3", "nyc3"},
      {"sfo3", "sfo3"},
      {"ams3", "ams3"},
      {"fra1", "fra1"},
      {"sgp1", "sgp1"}
    ]
  end

  defp region_options(:wasabi) do
    [
      {"us-east-1", "us-east-1"},
      {"us-east-2", "us-east-2"},
      {"us-west-1", "us-west-1"},
      {"eu-central-1", "eu-central-1"},
      {"ap-southeast-1", "ap-southeast-1"}
    ]
  end

  defp region_options(:backblaze_b2) do
    [
      {"us-west-001", "us-west-001"},
      {"us-west-002", "us-west-002"},
      {"us-east-005", "us-east-005"}
    ]
  end

  defp region_options(_), do: []

  defp normalize_params(params, selected_provider) do
    provider = provider_from_params(params["provider"], selected_provider)
    provider_changed? = provider != selected_provider

    params = maybe_default_region(params, provider, provider_changed?)
    params = maybe_default_endpoint(params, provider)

    {params, provider}
  end

  defp provider_from_params(nil, selected), do: selected
  defp provider_from_params("", _selected), do: nil

  defp provider_from_params(value, _selected) when is_binary(value) do
    Enum.find(Map.keys(@provider_data), fn key -> Atom.to_string(key) == value end)
  end

  defp maybe_default_region(params, provider, true) do
    region = Map.get(params, "region")

    if blank?(region) do
      case region_options(provider) do
        [{_label, value} | _] -> Map.put(params, "region", value)
        _ -> params
      end
    else
      params
    end
  end

  defp maybe_default_region(params, _provider, _changed), do: params

  defp maybe_default_endpoint(params, provider) do
    endpoint = Map.get(params, "endpoint_url")
    region = Map.get(params, "region")

    if blank?(endpoint) do
      case default_endpoint(provider, region) do
        nil -> params
        value -> Map.put(params, "endpoint_url", value)
      end
    else
      params
    end
  end

  defp default_endpoint(:aws_s3, region) when is_binary(region) and region != "" do
    "https://s3.#{region}.amazonaws.com"
  end

  defp default_endpoint(:digitalocean_spaces, region) when is_binary(region) and region != "" do
    "https://#{region}.digitaloceanspaces.com"
  end

  defp default_endpoint(:backblaze_b2, region) when is_binary(region) and region != "" do
    "https://s3.#{region}.backblazeb2.com"
  end

  defp default_endpoint(:wasabi, region) when is_binary(region) and region != "" do
    "https://s3.#{region}.wasabisys.com"
  end

  defp default_endpoint(:cloudflare_r2, _region) do
    "https://account-id.r2.cloudflarestorage.com"
  end

  defp default_endpoint(:minio, _region) do
    "https://minio.example.com"
  end

  defp default_endpoint(:custom, _region) do
    "https://storage.example.com"
  end

  defp default_endpoint(_, _), do: nil

  defp blank?(value), do: value in [nil, ""]

  defp normalize_secret_value(value) do
    case value do
      nil -> nil
      "" -> nil
      other -> other
    end
  end

  defp secret_input_type(true), do: "text"
  defp secret_input_type(false), do: "password"

  defp params_from_config(nil), do: %{}

  defp params_from_config(%S3Config{} = config) do
    %{
      "provider" => Atom.to_string(config.provider),
      "bucket_name" => config.bucket_name,
      "region" => config.region,
      "endpoint_url" => config.endpoint_url,
      "path_prefix" => config.path_prefix
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp s3_validator_from_session(session) do
    if Application.get_env(:micelio, :environment) == :test do
      session
      |> Map.get("s3_validator")
      |> maybe_existing_module()
    end
  end

  defp maybe_existing_module(nil), do: nil

  defp maybe_existing_module(module_name) when is_binary(module_name) do
    module = String.to_existing_atom(module_name)

    case Code.ensure_loaded(module) do
      {:module, _} -> module
      _ -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp format_date(%DateTime{} = datetime) do
    datetime
    |> DateTime.to_date()
    |> Date.to_iso8601()
  end

  defp step_entries(steps) do
    steps
    |> Enum.sort_by(fn {step, _status} -> step end)
  end

  defp step_label(step) do
    case step do
      :endpoint -> "Endpoint"
      :bucket -> "Bucket"
      :write -> "Write"
      :read -> "Read"
      :delete -> "Delete"
      :public_access -> "Public access"
      _ -> "Check"
    end
  end

  defp step_status_label(:ok), do: "OK"
  defp step_status_label(:warning), do: "Warning"

  defp step_status_label({:error, _message}), do: "Error"
  defp step_status_label(_), do: "Unknown"

  defp step_status_class(status) do
    case status do
      :ok -> "storage-settings-step storage-settings-step-ok"
      :warning -> "storage-settings-step storage-settings-step-warning"
      {:error, _message} -> "storage-settings-step storage-settings-step-error"
      _ -> "storage-settings-step"
    end
  end
end
