defmodule MicelioWeb.SandboxModuleController do
  use MicelioWeb, :controller

  @modules_root Application.app_dir(:micelio, "priv/sandbox_modules")

  def show(conn, %{"path" => path_parts}) do
    relative_path = Path.join(path_parts)
    full_path = Path.join(@modules_root, relative_path)

    if path_safe?(full_path) and File.regular?(full_path) do
      conn
      |> put_resp_content_type(content_type_for(relative_path))
      |> send_file(200, full_path)
    else
      send_resp(conn, 404, "Not found")
    end
  end

  defp path_safe?(path) do
    normalized = Path.expand(path)
    String.starts_with?(normalized, @modules_root)
  end

  defp content_type_for(path) do
    cond do
      String.ends_with?(path, ".ts") -> "text/typescript"
      String.ends_with?(path, ".js") -> "application/javascript"
      String.ends_with?(path, ".json") -> "application/json"
      true -> "text/plain"
    end
  end
end
