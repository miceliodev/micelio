defmodule MicelioWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: MicelioWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      role={if @kind == :error, do: "alert", else: "status"}
      class={[
        "flash-bar",
        @kind == :info && "flash-bar--info",
        @kind == :error && "flash-bar--error"
      ]}
      {@rest}
    >
      <div class="flash-bar-inner">
        <div class="flash-bar-text">
          <%= if @title do %>
            <strong>{@title}</strong>
            <span class="flash-bar-separator" aria-hidden="true"> · </span>
          <% end %>
          {msg}
        </div>

        <button
          type="button"
          class="flash-bar-dismiss"
          data-flash-dismiss
          data-flash-target={@id}
          phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide(to: "##{@id}")}
          aria-label={gettext("close")}
        >
          <span aria-hidden="true">×</span>
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="form-error">
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class="page-header">
      <div class="page-header-main">
        <h1 class="page-header-title">
          {render_slot(@inner_block)}
        </h1>
        <div :if={@subtitle != []} class="page-header-subtitle">
          {render_slot(@subtitle)}
        </div>
      </div>

      <div :if={@actions != []} class="page-header-actions">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc """
  Renders a clickable content card with title, subtitle, and description.

  ## Examples

      <.content_card navigate="/blog/my-post" id="post-1">
        <:title>My Post</:title>
        <:subtitle>Jan 14, 2026 by Pedro</:subtitle>
        <:description>A short summary of the post.</:description>
      </.content_card>
  """
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :id, :string, default: nil
  attr :class, :string, default: nil
  slot :title, required: true
  slot :subtitle
  slot :description

  def content_card(assigns) do
    ~H"""
    <.link
      :if={@navigate}
      navigate={@navigate}
      class={["content-card", @class]}
      id={@id}
    >
      <div class="content-card-title">{render_slot(@title)}</div>
      <div :if={@subtitle != []} class="content-card-subtitle">{render_slot(@subtitle)}</div>
      <div :if={@description != []} class="content-card-description">{render_slot(@description)}</div>
    </.link>
    <a
      :if={@href && !@navigate}
      href={@href}
      class={["content-card", @class]}
      id={@id}
    >
      <div class="content-card-title">{render_slot(@title)}</div>
      <div :if={@subtitle != []} class="content-card-subtitle">{render_slot(@subtitle)}</div>
      <div :if={@description != []} class="content-card-description">{render_slot(@description)}</div>
    </a>
    """
  end

  @doc """
  Renders a repository page header with breadcrumb and tab navigation.

  ## Examples

      <.repository_header account_handle="org" repository_handle="repo" active_tab={:settings}>
        Content here
      </.repository_header>
  """
  attr :account_handle, :string, required: true
  attr :repository_handle, :string, required: true
  attr :active_tab, :atom, required: true
  slot :inner_block, required: true

  def repository_header(assigns) do
    ~H"""
    <div class="repository-page">
      <div class="repository-header" id="repository-header">
        <div class="repository-header-info">
          <h1 class="repository-header-name">
            <svg
              class="repository-header-icon"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
              aria-hidden="true"
            >
              <path d="M3 19a9 9 0 0 1 9 0a9 9 0 0 1 9 0" />
              <path d="M3 6a9 9 0 0 1 9 0a9 9 0 0 1 9 0" />
              <path d="M3 6v13" />
              <path d="M12 6v13" />
              <path d="M21 6v13" />
            </svg>
            <.link navigate={"/#{@account_handle}"} class="repository-header-owner">
              {@account_handle}
            </.link>
            <span class="repository-header-sep">/</span>
            <.link
              navigate={"/#{@account_handle}/#{@repository_handle}"}
              class="repository-header-repo"
            >
              {@repository_handle}
            </.link>
          </h1>
        </div>
      </div>
      <nav class="repository-tabs" aria-label="Repository navigation" id="repository-tabs">
        <.link
          navigate={"/#{@account_handle}/#{@repository_handle}"}
          class={["repository-tab", @active_tab == :code && "is-active"]}
        >
          <svg
            class="repository-tab-icon"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M10 20l4-16m4.5 4l4.5 4-4.5 4M5.5 8L1 12l4.5 4" />
          </svg>
          {gettext("Code")}
        </.link>
        <.link
          navigate={"/#{@account_handle}/#{@repository_handle}/sessions"}
          class={["repository-tab", @active_tab == :sessions && "is-active"]}
        >
          <svg
            class="repository-tab-icon"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M12 8v4l3 3" />
            <circle cx="12" cy="12" r="9" />
          </svg>
          {gettext("Sessions")}
        </.link>
        <.link
          navigate={"/#{@account_handle}/#{@repository_handle}/prs"}
          class={["repository-tab", @active_tab == :prompt_requests && "is-active"]}
        >
          <svg
            class="repository-tab-icon"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M8 9h8" />
            <path d="M8 13h6" />
            <path d="M9 18h-3a3 3 0 0 1-3-3V7a3 3 0 0 1 3-3h12a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3h-3l-3 3-3-3z" />
          </svg>
          {gettext("Prompt Requests")}
        </.link>
        <.link
          navigate={"/#{@account_handle}/#{@repository_handle}/settings"}
          class={["repository-tab", @active_tab == :settings && "is-active"]}
        >
          <svg
            class="repository-tab-icon"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
            aria-hidden="true"
          >
            <path d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 0 0 2.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 0 0 1.066 2.573c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 0 0-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 0 0-2.573 1.066c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 0 0-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 0 0-1.066-2.573c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 0 0 1.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
            <circle cx="12" cy="12" r="3" />
          </svg>
          {gettext("Settings")}
        </.link>
      </nav>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Renders a settings page layout with a sidebar navigation and content area.

  ## Examples

      <.settings_layout base_path={~p"/\#{@organization.account.handle}/\#{@repository.handle}/settings"} active={:general}>
        <.header>Repository settings</.header>
      </.settings_layout>
  """
  attr :base_path, :string, required: true
  attr :active, :atom, required: true
  slot :inner_block, required: true

  def settings_layout(assigns) do
    ~H"""
    <div class="settings-layout">
      <aside class="settings-sidebar">
        <nav class="settings-sidebar-nav">
          <.link
            navigate={@base_path}
            class={["settings-sidebar-link", @active == :general && "settings-sidebar-link-active"]}
          >
            General
          </.link>
          <.link
            navigate={"#{@base_path}/webhooks"}
            class={["settings-sidebar-link", @active == :webhooks && "settings-sidebar-link-active"]}
          >
            Webhooks
          </.link>
        </nav>
      </aside>
      <div class="settings-content">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a small badge (optionally as a link).

  ## Examples

      <.badge>v0.1.0</.badge>
      <.badge variant={:solid} caps>release</.badge>
      <.badge href={~p"/blog/rss"}>RSS</.badge>
  """
  attr :variant, :atom, values: [:soft, :solid], default: :soft
  attr :mono, :boolean, default: false
  attr :caps, :boolean, default: false
  attr :active, :boolean, default: false
  attr :href, :string, default: nil
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def badge(assigns) do
    interactive? =
      not is_nil(assigns.href) or not is_nil(assigns.navigate) or not is_nil(assigns.patch)

    assigns = assign(assigns, :interactive?, interactive?)

    ~H"""
    <%= if @interactive? do %>
      <.link
        href={@href}
        navigate={@navigate}
        patch={@patch}
        class={badge_classes(@variant, @mono, @caps, @active, @class, true)}
        {@rest}
      >
        {render_slot(@inner_block)}
      </.link>
    <% else %>
      <span class={badge_classes(@variant, @mono, @caps, @active, @class, false)} {@rest}>
        {render_slot(@inner_block)}
      </span>
    <% end %>
    """
  end

  defp badge_classes(variant, mono?, caps?, active?, extra_class, interactive?) do
    [
      "badge",
      variant == :solid && "badge--solid",
      variant == :soft && "badge--soft",
      mono? && "badge--mono",
      caps? && "badge--caps",
      active? && "is-active",
      interactive? && "badge--interactive",
      extra_class
    ]
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(MicelioWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(MicelioWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  @doc """
  Renders a Gravatar avatar image based on an email address.

  Uses MD5 hash of the email to generate the Gravatar URL.
  Falls back to a "mystery person" default image if no Gravatar exists.

  ## Examples

      <.gravatar email={@user.email} />
      <.gravatar email={@user.email} size={64} />
      <.gravatar email={@user.email} size={48} class="rounded-full" />
  """
  attr :email, :string, required: true, doc: "the email address to generate avatar for"

  attr :size, :integer,
    default: 48,
    doc: "the size in pixels (will be used for both width and height)"

  attr :class, :string, default: nil, doc: "additional CSS classes"
  attr :alt, :string, default: "", doc: "alt text for the image"
  attr :rest, :global

  def gravatar(assigns) do
    assigns = assign(assigns, :url, gravatar_url(assigns.email, assigns.size))

    ~H"""
    <img
      src={@url}
      width={@size}
      height={@size}
      alt={@alt}
      class={@class}
      loading="lazy"
      decoding="async"
      referrerpolicy="no-referrer"
      {@rest}
    />
    """
  end

  @doc """
  Generates a Gravatar URL for the given email address.

  ## Parameters
    - email: The email address to generate the Gravatar URL for
    - size: The size of the image in pixels (default: 48)

  ## Examples

      iex> MicelioWeb.CoreComponents.gravatar_url("test@example.com")
      "https://www.gravatar.com/avatar/55502f40dc8b7c769880b10874abc9d0?s=48&d=mp&r=g"

  """
  def gravatar_url(email, size \\ 48) when is_binary(email) and is_integer(size) do
    email = email |> String.trim() |> String.downcase()
    hash = :crypto.hash(:md5, email) |> Base.encode16(case: :lower)
    "https://www.gravatar.com/avatar/#{hash}?s=#{size}&d=mp&r=g"
  end

  @doc """
  Renders a language selector dropdown for locale switching.

  For marketing pages, it renders links to locale-prefixed URLs.
  For dashboard pages, it can POST to update the user's locale preference.

  ## Examples

      <.language_selector current_locale={@locale} />
      <.language_selector current_locale={@locale} current_path="/about" />
  """
  attr :current_locale, :string, required: true, doc: "the currently selected locale"
  attr :current_path, :string, default: "/", doc: "the current path for building locale URLs"
  attr :class, :string, default: nil, doc: "additional CSS classes"

  @supported_locales [
    {"en", "English"},
    {"ko", "한국어"},
    {"zh_CN", "简体中文"},
    {"zh_TW", "繁體中文"},
    {"ja", "日本語"}
  ]

  def language_selector(assigns) do
    assigns = assign(assigns, :locales, @supported_locales)

    ~H"""
    <div
      class={["language-selector", @class]}
      role="navigation"
      aria-label={gettext("Language selection")}
    >
      <label for="language-select" class="sr-only">{gettext("Select language")}</label>
      <select
        id="language-select"
        name="locale"
        class="compact-select"
        aria-label={gettext("Select language")}
        onchange="window.location.href = this.value"
      >
        <%= for {code, name} <- @locales do %>
          <%= if code == @current_locale do %>
            <option value={locale_path(@current_path, code)} selected>
              {name}
            </option>
          <% else %>
            <option value={locale_path(@current_path, code)}>
              {name}
            </option>
          <% end %>
        <% end %>
      </select>
    </div>
    """
  end

  @locale_codes ~w(ko zh_CN zh_TW ja)

  defp locale_path(path, "en"), do: path
  defp locale_path("/", locale), do: "/#{locale}"

  defp locale_path(path, locale) do
    # Remove any existing locale prefix and add the new one
    path_without_locale =
      case String.split(path, "/", parts: 3) do
        ["", existing_locale | rest] when existing_locale in @locale_codes ->
          "/" <> Enum.join(rest, "/")

        _ ->
          path
      end

    if locale == "en" do
      path_without_locale
    else
      "/#{locale}#{path_without_locale}"
    end
  end

  @doc """
  Renders a GitHub-style activity/contribution graph.

  Shows activity over the past N weeks as a grid of colored cells.
  Each cell represents one day, with color intensity based on activity count.

  ## Examples

      <.activity_graph activity_counts={@activity_counts} />
      <.activity_graph activity_counts={@activity_counts} weeks={26} />
  """
  attr :activity_counts, :map, required: true, doc: "map of Date => count"
  attr :weeks, :integer, default: 52, doc: "number of weeks to display"
  attr :class, :string, default: nil, doc: "additional CSS classes"

  def activity_graph(assigns) do
    today = Date.utc_today()
    # Find the Sunday of the current week
    today_weekday = Date.day_of_week(today, :sunday)
    last_sunday = Date.add(today, -(today_weekday - 1))
    # Start from N weeks ago on a Sunday
    start_date = Date.add(last_sunday, -(assigns.weeks * 7) + 7)

    # Build the grid data: list of {week_index, day_of_week (0-6), date, count}
    dates =
      Date.range(start_date, today)
      |> Enum.to_list()

    weeks_data =
      dates
      |> Enum.with_index()
      |> Enum.map(fn {date, idx} ->
        week_idx = div(idx, 7)
        day_idx = Date.day_of_week(date, :sunday) - 1
        count = Map.get(assigns.activity_counts, date, 0)
        {week_idx, day_idx, date, count}
      end)
      |> Enum.group_by(fn {week_idx, _, _, _} -> week_idx end)

    max_count = assigns.activity_counts |> Map.values() |> Enum.max(fn -> 0 end)
    total_count = assigns.activity_counts |> Map.values() |> Enum.sum()

    assigns =
      assigns
      |> assign(:weeks_data, weeks_data)
      |> assign(:max_count, max_count)
      |> assign(:total_count, total_count)
      |> assign(:cell_size, 11)
      |> assign(:cell_gap, 3)

    ~H"""
    <div class={["activity-graph", @class]} aria-label="Activity graph">
      <div class="activity-graph-container">
        <svg
          class="activity-graph-svg"
          width={@weeks * (@cell_size + @cell_gap)}
          height={7 * (@cell_size + @cell_gap)}
          role="img"
          aria-label={"#{@total_count} contributions"}
        >
          <%= for {week_idx, days} <- @weeks_data do %>
            <%= for {_week, day_idx, date, count} <- days do %>
              <rect
                x={week_idx * (@cell_size + @cell_gap)}
                y={day_idx * (@cell_size + @cell_gap)}
                width={@cell_size}
                height={@cell_size}
                rx="2"
                class={activity_cell_class(count, @max_count)}
                data-date={Date.to_iso8601(date)}
                data-count={count}
              >
                <title>
                  {Date.to_iso8601(date)}: {count} {ngettext("contribution", "contributions", count)}
                </title>
              </rect>
            <% end %>
          <% end %>
        </svg>
      </div>
      <div class="activity-graph-legend">
        <span class="activity-graph-legend-label">Less</span>
        <span class="activity-graph-cell activity-graph-cell--0"></span>
        <span class="activity-graph-cell activity-graph-cell--1"></span>
        <span class="activity-graph-cell activity-graph-cell--2"></span>
        <span class="activity-graph-cell activity-graph-cell--3"></span>
        <span class="activity-graph-cell activity-graph-cell--4"></span>
        <span class="activity-graph-legend-label">More</span>
      </div>
    </div>
    """
  end

  defp activity_cell_class(count, max_count) do
    level = activity_level(count, max_count)
    "activity-graph-cell activity-graph-cell--#{level}"
  end

  defp activity_level(0, _max), do: 0
  defp activity_level(_count, 0), do: 0

  defp activity_level(count, max) do
    ratio = count / max

    cond do
      ratio <= 0.25 -> 1
      ratio <= 0.5 -> 2
      ratio <= 0.75 -> 3
      true -> 4
    end
  end
end
