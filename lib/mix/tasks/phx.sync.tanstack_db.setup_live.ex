# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
# SPDX-FileCopyrightText: 2026 Santiago Papiernik <https://github.com/spapiernik/phoenix_sync_fix/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Phx.Sync.TanstackDb.SetupLive.Docs do
  @moduledoc false

  @spec short_doc() :: String.t()
  def short_doc do
    "Convert a Phoenix application to use a Vite + Tanstack DB based frontend"
  end

  @spec example() :: String.t()
  def example do
    "mix phx.sync.tanstack_db.setup"
  end

  @spec long_doc() :: String.t()
  def long_doc do
    """
    #{short_doc()}

    This is a very invasive task that does the following:

    - Removes `esbuild` with `vite` and removes the Elixir integration with
      tailwindcss

    - Adds a `package.json` with the required dependencies for `@tanstack/db`,
      `@tanstack/router`, `react` and `tailwind`

    - Drops in some example routes, schemas, collections and mutation code

    - Replaces the default `root.html.heex` layout to one suitable for a
      react-based SPA

    For this reason we recommend only running this on a fresh Phoenix project
    (with `Phoenix.Sync` installed).

    ## Example

    ```sh
    # install igniter.new
    mix archive.install hex igniter_new

    # create a new phoenix application and install phoenix_sync in `embedded` mode
    mix igniter.new my_app --install phoenix_sync --with phx.new --sync-mode embedded

    # setup my_app to use tanstack db
    #{example()}
    ```

    ## Options

    * `--sync-pnpm` - Use `pnpm` as package manager if available (default)
    * `--no-sync-pnpm` - Use `npm` as package manager even if `pnpm` is installed
    """
  end
end


if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Phx.Sync.TanstackDb.SetupLive do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias PhoenixSyncFix.Installer.{
      Framework,
      Layout,
      PackageJson,
      Vite
    }

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :phoenix_sync_fix,
        installs: [],
        example: __MODULE__.Docs.example(),
        schema: [],
        defaults: [],
        composes: [],
        extra_args?: true
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      app_name = Igniter.Project.Application.app_name(igniter)
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      
      framework = "react"
      preset = "tanstack_db"
      bundler = "vite"
      use_bun = true

      # Validate
      igniter = Framework.validate_framework(igniter, framework)
      igniter = Framework.validate_preset(igniter, preset)
      igniter = Framework.validate_bundler(igniter, bundler)
      igniter = validate_tanstack_db_constraints(igniter, framework, bundler, preset)

      # Core setup (always runs)
      igniter =
        igniter
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
        |> maybe_add_caddyfile(preset)
        |> maybe_add_ingest_flow(preset, web_module)
        |> Vite.maybe_fix_runtime_manifest_cache(bundler, app_name)

      # Framework-specific setup
      igniter =
        setup_framework(igniter, app_name, web_module, framework, preset, bundler, use_bun)

      # Finalize
      igniter = Igniter.add_task(igniter, "assets.setup")
      igniter
    end

    defp validate_tanstack_db_constraints(igniter, framework, bundler, preset) do
      use_tanstack_db = preset == "tanstack_db"
      supported_frameworks = ["react"]
      
      cond do
        use_tanstack_db and is_nil(framework) ->
          Igniter.add_issue(igniter, "Tanstack DB requires a framework to be specified.")

        use_tanstack_db and framework not in supported_frameworks ->
          Igniter.add_issue(igniter, "#{String.capitalize(framework)} is not currently supported with Tanstack DB.")

        use_tanstack_db and bundler != "vite" ->
          Igniter.add_issue(igniter, "Tanstack DB currently only supports vite.")

        true ->
          igniter
      end
    end

    # -- Framework dispatch --

    defp setup_framework(igniter, app_name, web_module, framework, preset, bundler, use_bun) do
      igniter
      |> PackageJson.create_package_json(bundler, framework, preset)
      |> Framework.create_index_page(framework, preset)
      |> Framework.update_tsconfig(framework, preset, bundler)
      |> setup_bundler(app_name, bundler, use_bun, framework, preset)
      |> Layout.create_spa_root_layout(web_module, bundler, framework, preset)
      |> Layout.create_or_update_page_controller(web_module,
        use_spa_layout: true
      )
      |> Layout.create_index_template(web_module, bundler, framework)
      |> maybe_update_router_for_tanstack_db(preset, web_module)
    end

    defp setup_bundler(igniter, _app_name, "vite", _use_bun, framework, preset) do
      Vite.update_vite_config_with_framework(igniter, framework, preset)
    end

    defp maybe_update_router_for_tanstack_db(igniter, "tanstack_db", web_module) do
      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_path = Rewrite.Source.get(source, :path)

          igniter
          |> ensure_lv_route(router_path, web_module)
          |> ensure_catch_all_route_at_end(router_path, web_module)

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router. Please manually update routes for TanStack DB setup."
          )
      end
    end

    defp ensure_lv_route(igniter, router_path, web_module) do
      Igniter.update_file(igniter, router_path, fn source ->
        content = source.content

        updated =
          cond do
            String.contains?(content, "get \"/lv\", PageController, :home") ->
              content

            String.contains?(content, "get \"/\", PageController, :home") ->
              String.replace(
                content,
                "get \"/\", PageController, :home",
                "get \"/lv\", PageController, :home"
              )

            true ->
              insert_scope_before_router_end(
                content,
                """
                  scope "/", #{inspect(web_module)} do
                    pipe_through :browser

                    get "/lv", PageController, :home
                  end
                """
              )
          end

        if updated == content do
          source
        else
          Rewrite.Source.update(source, :content, updated)
        end
      end)
    end

    defp ensure_catch_all_route_at_end(igniter, router_path, web_module) do
      Igniter.update_file(igniter, router_path, fn source ->
        content = source.content

        catch_all_line = ~s|get "/*page", PageController, :index|

        content_without_existing_catch_all =
          String.replace(
            content,
            ~r/\n[ \t]*get "\/\*page", PageController, :index[ \t]*\n?/,
            "\n"
          )

        updated =
          if String.contains?(content, catch_all_line) or
               String.contains?(content_without_existing_catch_all, ~s|scope "/", #{inspect(web_module)} do|) do
            insert_scope_before_router_end(
              content_without_existing_catch_all,
              """
  scope "/", #{inspect(web_module)} do
    pipe_through :browser
    
    # Forward all routes onto the root layout since tanstack router does our routing
    get "/*page", PageController, :index
  end
"""
            )
          else
            content
          end

        if updated == content do
          source
        else
          Rewrite.Source.update(source, :content, updated)
        end
      end)
    end

    defp insert_scope_before_router_end(content, scope_block) do
      normalized_scope = String.trim_trailing(scope_block)

      String.replace(content, ~r/\n+\s*end\s*$/, "\n\n" <> normalized_scope <> "\nend\n")
    end

    defp maybe_add_caddyfile(igniter, "tanstack_db") do
      rendered =
        :phoenix_sync_fix
        |> :code.priv_dir()
        |> Path.join("igniter/phx.sync.tanstack_db/Caddyfile.eex")
        |> EEx.eval_file([])

      Igniter.create_or_update_file(igniter, "Caddyfile", rendered <> "\n", fn source ->
        if source.content == rendered <> "\n" do
          source
        else
          Rewrite.Source.update(source, :content, rendered <> "\n")
        end
      end)
    end

    defp maybe_add_caddyfile(igniter, _preset), do: igniter

    defp maybe_add_ingest_flow(igniter, "tanstack_db", web_module) do
      igniter
      |> add_ingest_scope(web_module)
      |> create_ingest_controller(web_module)
    end

    defp maybe_add_ingest_flow(igniter, _preset, _web_module), do: igniter

    defp add_ingest_scope(igniter, web_module) do
      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_content = Rewrite.Source.get(source, :content)

          if String.contains?(router_content, "scope \"/ingest\"") do
            igniter
          else
            Igniter.update_file(igniter, Rewrite.Source.get(source, :path), fn src ->
              content = src.content

              ingest_scope = """
              
  scope "/ingest", #{inspect(web_module)} do
    pipe_through :api

    # example router for accepting optimistic writes from the client
    # See: https://tanstack.com/db/latest/docs/overview#making-optimistic-mutations
    # post "/mutations", Controllers.IngestController, :ingest
  end
"""

              updated =
                if String.contains?(content, ~s|scope "/ingest"|) do
                  content
                else
                  String.replace(content, ~r/\nend\s*$/, "\n" <> ingest_scope <> "end\n")
                end

              if updated == content do
                src
              else
                Rewrite.Source.update(src, :content, updated)
              end
            end)
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router. Please manually add the /ingest scope for TanStack DB."
          )
      end
    end

    defp create_ingest_controller(igniter, web_module) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")
      web_folder = Macro.underscore(clean_web_module)

      controller_path =
        Path.join(["lib", web_folder, "controllers", "ingest_controller.ex"])

      controller_module = "#{clean_web_module}.IngestController"

      controller_content = """
      defmodule #{controller_module} do
        use #{clean_web_module}, :controller

        # See https://hexdocs.pm/phoenix_sync/readme.html#write-path-sync
        # alias Phoenix.Sync.Writer
        #
        # def ingest(%{assigns: %{current_user: user}} = conn, %{"mutations" => mutations}) do
        #   {:ok, txid, _changes} =
        #     Writer.new()
        #     |> Writer.allow(
        #       Todos.Todo,
        #       accept: [:insert],
        #       check: &Ingest.check_event(&1, user)
        #     )
        #     |> Writer.apply(mutations, Repo, format: Writer.Format.TanstackDB)
        #
        #   json(conn, %{txid: txid})
        # end
      end
      """

      Igniter.create_new_file(igniter, controller_path, controller_content, on_exists: :warning)
    end
  end
else
  defmodule Mix.Tasks.Phx.Sync.TanstackDb.SetupLive do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    @impl Mix.Task
    def run(_argv) do
      Mix.shell().error("""
      The task 'phx.sync.tanstack_db.setup_live' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end