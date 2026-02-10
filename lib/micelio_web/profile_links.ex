defmodule MicelioWeb.ProfileLinks do
  @moduledoc false

  alias Micelio.Accounts.User

  def social_links(%User{} = user) do
    [
      %{label: "Website", url: user.website_url, icon: "hero-globe-alt"},
      %{label: "Twitter/X", url: user.twitter_url, icon: "hero-hashtag"},
      %{label: "GitHub", url: user.github_url, icon: "hero-code-bracket"},
      %{label: "GitLab", url: user.gitlab_url, icon: "hero-square-3-stack-3d"},
      %{label: "Mastodon", url: user.mastodon_url, icon: "hero-chat-bubble-left-right"},
      %{label: "LinkedIn", url: user.linkedin_url, icon: "hero-user-group"}
    ]
    |> Enum.filter(&(&1.url && String.trim(&1.url) != ""))
  end

  def social_links(_), do: []
end
