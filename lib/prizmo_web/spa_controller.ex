defmodule PrizmoWeb.SPAController do
  @moduledoc false

  use PrizmoWeb, :controller

  @dev_css_path "/assets/css/app.css"
  @dev_js_path "/assets/lib/prizmo_web/spa/index.tsx"

  # sobelow_skip ["XSS.HTML"]
  def index conn, _params do
    %{css_path: css_path, js_path: js_path} = asset_paths()

    html(conn, spa_shell(css_path, js_path, Plug.CSRFProtection.get_csrf_token()))
  end

  defp asset_paths do
    if dev_assets?() do
      %{css_path: @dev_css_path, js_path: @dev_js_path}
    else
      built_asset_paths()
    end
  end

  defp dev_assets? do
    :prizmo
    |> Application.get_env(:spa_assets, [])
    |> Keyword.get(:mode, :built)
    |> Kernel.==(:dev)
  end

  defp built_asset_paths do
    %{
      css_path: static_path("/assets/css/#{manifest_file("css", "app.css")}"),
      js_path: static_path("/assets/js/#{manifest_file("js", "index.js")}")
    }
  end

  defp manifest_file(kind, entry) do
    manifest = read_manifest!("assets/#{kind}/manifest.json")

    manifest
    |> Map.fetch!(entry)
    |> Map.fetch!("file")
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp read_manifest!(path) do
    manifest_path = priv_static_path(path)

    manifest_path
    |> File.read!()
    |> Jason.decode!()
  end

  defp priv_static_path(path) do
    app_path = Application.app_dir(:prizmo, Path.join("priv/static", path))
    source_path = Path.expand(Path.join("priv/static", path))

    if File.exists?(app_path), do: app_path, else: source_path
  end

  defp static_path(path), do: PrizmoWeb.Endpoint.static_path(path)

  defp spa_shell(css_path, js_path, csrf_token) do
    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="csrf-token" content="#{csrf_token}">
        <title>Prizmo</title>
        <link rel="stylesheet" href="#{css_path}">
        <script type="module" src="#{js_path}"></script>
      </head>
      <body>
        <div id="app"></div>
      </body>
    </html>
    """
  end
end
