# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
# SPDX-FileCopyrightText: 2026 Santiago Papiernik <https://github.com/spapiernik/phoenix_sync_fix/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.Phx.Sync.TanstackDb.SetupLive2.Docs do
  @moduledoc false
  
  @spec short_doc() :: String.t()
  def short_doc(), do: ""

  @spec example() :: String.t()
  def example(), do: ""

  @spec long_doc() :: String.t()
  def long_doc(), do: ""
end


if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Phx.Sync.TanstackDb.SetupLive2 do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()

    use Igniter.Mix.Task

    alias PhoenixSyncFix.Installer.{
      Esbuild,
      Framework,
      Inertia,
      Layout,
      PackageJson,
      Vite
    }

    @impl Igniter.Mix.Task
    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{
        group: :phoenix_sync_fix,
        installs: [],
        schema: [framework: :string, preset: :string, bundler: :string, bun: :boolean, inertia: :boolean],
        defaults: [framework: nil, preset: nil, bundler: nil, bun: false, inertia: false],
        composes: [],
        extra_args?: true
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      # phoenix_vite_dep = {:phoenix_vite, "~> 0.4.2"}
      # phoenix_vite_triggers = [{"--bundler", "vite"}, {"--preset", "tanstack_db"}]
          
      # installs =
      #   igniter.args.argv
      #   |> Enum.chunk_every(2, 1, :discard)
      #   |> Enum.find_value(fn [flag, val] ->
      #     if {flag, val} in phoenix_vite_triggers do
      #       [phoenix_vite_dep]
      #     else
      #       nil
      #     end
      #   end) || []
        
      app_name = Igniter.Project.Application.app_name(igniter)
      web_module = Igniter.Libs.Phoenix.web_module(igniter)
      yes? = igniter.args.options[:yes] || false

      # Resolve options: CLI flags take precedence, otherwise prompt interactively
      framework = resolve_framework(igniter, yes?)
      preset = resolve_preset(igniter, yes?)
      bundler = resolve_bundler(igniter, yes?)
      use_bun = resolve_package_manager(igniter, yes?)
      use_inertia = resolve_inertia(igniter, framework, bundler, yes?)

      # Validate
      igniter = Framework.validate_framework(igniter, framework)
      igniter = Framework.validate_preset(igniter, preset)
      igniter = Framework.validate_bundler(igniter, bundler)
      igniter = validate_inertia_constraints(igniter, framework, bundler, use_inertia)
      igniter = validate_tanstack_db_constraints(igniter, framework, bundler, preset)

      # Core setup (always runs)
      # Note: phoenix_vite is installed via `installs` in info/2 when --bundler vite
      igniter =
        igniter
        |> Igniter.Project.IgniterConfig.add_extension(Igniter.Extensions.Phoenix)
        |> maybe_add_caddyfile(preset)
        |> maybe_add_ingest_flow(preset, web_module)
        |> Vite.maybe_fix_runtime_manifest_cache(bundler, app_name)

      # # Framework-specific setup
      igniter =
        setup_framework(igniter, app_name, web_module, framework, preset, bundler, use_bun, use_inertia)

      # Finalize
      igniter =
        if framework do
          Igniter.add_task(igniter, "assets.setup")
        else
          igniter
        end

      # add_next_steps_notice(igniter, framework, bundler, use_inertia)
      igniter
    end

    # -- Interactive prompt resolution --

    defp resolve_framework(igniter, yes?) do
      case Keyword.get(igniter.args.options, :framework) do
        nil ->
          if yes? do
            nil
          else
            Igniter.Util.IO.select(
              "Which frontend framework would you like to use?",
              [nil, "react", "vue", "svelte", "solid"],
              display: fn
                nil -> "None (TypeScript RPC only)"
                f -> framework_display_name(f)
              end,
              default: nil
            )
          end

        value ->
          value
      end
    end
    
    defp resolve_preset(igniter, yes?) do
      case Keyword.get(igniter.args.options, :preset) do
        nil ->
          if yes? do
            nil
          else
            Igniter.Util.IO.select(
              "Which preset would you like to use?",
              [nil, "tanstack_db"],
              display: fn
                nil -> "None"
                p -> preset_display_name(p)
              end,
              default: nil
            )
          end
          
        value ->
          value
      end
    end

    defp resolve_bundler(igniter, yes?) do
      case Keyword.get(igniter.args.options, :bundler) do
        nil ->
          if yes? do
            "vite"
          else
            Igniter.Util.IO.select(
              "Which bundler would you like to use?",
              ["vite", "esbuild"],
              display: fn
                "vite" -> bundler_display_name("vite")
                "esbuild" -> "#{bundler_display_name("esbuild")} (Phoenix default)"
              end,
              default: "vite"
            )
          end

        value ->
          value
      end
    end

    defp resolve_package_manager(igniter, yes?) do
      case Keyword.get(igniter.args.options, :bun) do
        nil ->
          if yes?, do: false, else: Igniter.Util.IO.yes?("Use Bun instead of npm?")

        value ->
          value
      end
    end

    defp resolve_inertia(igniter, framework, bundler, yes?) do
      cond do
        is_nil(framework) ->
          false

        framework == "solid" ->
          false

        bundler == "vite" ->
          false

        Keyword.get(igniter.args.options, :inertia) != nil ->
          Keyword.get(igniter.args.options, :inertia)

        yes? ->
          false

        true ->
          Igniter.Util.IO.yes?("Use Inertia.js for server-side rendering?")
      end
    end

    defp validate_inertia_constraints(igniter, framework, bundler, use_inertia) do
      cond do
        use_inertia and is_nil(framework) ->
          Igniter.add_issue(igniter, "Inertia requires a framework to be specified.")

        use_inertia and framework == "solid" ->
          Igniter.add_issue(igniter, "Solid is not currently supported with Inertia.")

        use_inertia and bundler == "vite" ->
          Igniter.add_issue(igniter, "Inertia currently only supports esbuild.")

        true ->
          igniter
      end
    end

    defp validate_tanstack_db_constraints(igniter, framework, bundler, preset) do
      use_tanstack_db = preset == "tanstack_db"
      supported_frameworks = ["react"]
      
      cond do
        use_tanstack_db and is_nil(framework) ->
          Igniter.add_issue(igniter, "Tanstack DB requires a framework to be specified.")

        use_tanstack_db and framework not in supported_frameworks ->
          Igniter.add_issue(igniter, "#{String.capitalize(framework)} is not currently supported with Tanstack DB.")

        use_tanstack_db and bundler == "esbuild" ->
          Igniter.add_issue(igniter, "Tanstack DB currently only supports vite.")

        true ->
          igniter
      end
    end

    # -- Framework dispatch --

    defp setup_framework(igniter, _app_name, _web_module, nil, _preset, _bundler, _use_bun, _use_inertia) do
      igniter
    end

    defp setup_framework(igniter, app_name, web_module, framework, _preset, bundler, use_bun, true) do
      igniter
      |> PackageJson.create_package_json(bundler, framework)
      |> Framework.update_tsconfig(framework)
      |> Inertia.setup(app_name, web_module, bundler, use_bun, framework)
    end

    defp setup_framework(igniter, app_name, web_module, framework, preset, bundler, use_bun, false) do
      igniter
      |> PackageJson.create_package_json(bundler, framework, preset)
      |> Framework.create_index_page(framework, preset)
      |> Framework.update_tsconfig(framework, preset, bundler)
      |> setup_bundler(app_name, bundler, use_bun, framework, preset)
      |> Layout.create_spa_root_layout(web_module, bundler, framework, preset)
      |> Layout.create_or_update_page_controller(web_module,
        use_spa_layout: bundler in ["vite", "esbuild"]
      )
      |> Layout.create_index_template(web_module, bundler, framework)
      |> maybe_update_router_for_tanstack_db(preset, web_module)
      # |> Layout.add_page_index_route(web_module)
    end

    defp setup_bundler(igniter, app_name, "esbuild", use_bun, framework, _preset)
         when framework in ["vue", "svelte", "solid"] do
      igniter
      |> Esbuild.create_esbuild_script(framework)
      |> Esbuild.update_esbuild_config_with_script(app_name, use_bun)
      |> Esbuild.update_root_layout_for_esbuild()
    end

    defp setup_bundler(igniter, app_name, "esbuild", use_bun, framework, _preset) do
      igniter
      |> Esbuild.update_esbuild_config(app_name, use_bun, framework)
      |> Esbuild.update_root_layout_for_esbuild()
    end

    defp setup_bundler(igniter, _app_name, "vite", _use_bun, framework, preset) do
      Vite.update_vite_config_with_framework(igniter, framework, preset)
    end

    defp setup_bundler(igniter, _app_name, _bundler, _use_bun, _framework), do: igniter

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

    defp maybe_update_router_for_tanstack_db(igniter, _preset, _web_module), do: igniter

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

    # -- Core setup --

    defp add_ash_typescript_config(igniter) do
      igniter
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:output_file],
        "assets/js/ash_rpc.ts"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:run_endpoint],
        "/rpc/run"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:validate_endpoint],
        "/rpc/validate"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:input_field_formatter],
        :camel_case
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:output_field_formatter],
        :camel_case
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:require_tenant_parameters],
        false
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:generate_zod_schemas],
        false
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:generate_phx_channel_rpc_actions],
        false
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:generate_validation_functions],
        true
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:zod_import_path],
        "zod"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:zod_schema_suffix],
        "ZodSchema"
      )
      |> Igniter.Project.Config.configure_new(
        "config.exs",
        :ash_typescript,
        [:phoenix_import_path],
        "phoenix"
      )
    end

    defp create_rpc_controller(igniter, app_name, web_module) do
      clean_web_module = web_module |> to_string() |> String.replace_prefix("Elixir.", "")

      controller_content = """
      defmodule #{clean_web_module}.AshTypescriptRpcController do
        use #{clean_web_module}, :controller

        def run(conn, params) do
          result = AshTypescript.Rpc.run_action(:#{app_name}, conn, params)
          json(conn, result)
        end

        def validate(conn, params) do
          result = AshTypescript.Rpc.validate_action(:#{app_name}, conn, params)
          json(conn, result)
        end
      end
      """

      web_folder = Macro.underscore(clean_web_module)

      controller_path =
        Path.join(["lib", web_folder, "controllers", "ash_typescript_rpc_controller.ex"])

      Igniter.create_new_file(igniter, controller_path, controller_content, on_exists: :warning)
    end

    defp add_rpc_routes(igniter, web_module) do
      run_endpoint = Application.get_env(:ash_typescript, :run_endpoint)
      validate_endpoint = Application.get_env(:ash_typescript, :validate_endpoint)

      {igniter, router_module} = Igniter.Libs.Phoenix.select_router(igniter)

      case Igniter.Project.Module.find_module(igniter, router_module) do
        {:ok, {igniter, source, _zipper}} ->
          router_content = Rewrite.Source.get(source, :content)

          routes_to_add =
            []
            |> maybe_add_route(
              router_content,
              "AshTypescriptRpcController, :run",
              "  post \"#{run_endpoint}\", AshTypescriptRpcController, :run"
            )
            |> maybe_add_route(
              router_content,
              "AshTypescriptRpcController, :validate",
              "  post \"#{validate_endpoint}\", AshTypescriptRpcController, :validate"
            )

          if routes_to_add != [] do
            routes_string = Enum.join(Enum.reverse(routes_to_add), "\n") <> "\n"

            Igniter.Libs.Phoenix.append_to_scope(igniter, "/", routes_string,
              arg2: web_module,
              placement: :after
            )
          else
            igniter
          end

        {:error, igniter} ->
          Igniter.add_warning(
            igniter,
            "Could not find router. Please manually add RPC routes."
          )
      end
    end

    defp maybe_add_route(routes, router_content, check, route) do
      if String.contains?(router_content, check), do: routes, else: [route | routes]
    end

    # -- Next steps notice --

    defp add_next_steps_notice(igniter, nil, _bundler, _use_inertia) do
      Igniter.add_notice(igniter, """
      AshTypescript installed!

      Next Steps:
      1. Configure your domain with the AshTypescript.Rpc extension
      2. Add typescript_rpc configurations for your resources
      3. Generate TypeScript types: mix ash_typescript.codegen
      4. Start using type-safe RPC functions in your frontend!

      Documentation: https://hexdocs.pm/ash_typescript
      """)
    end

    defp add_next_steps_notice(igniter, framework, bundler, use_inertia) do
      name = framework_display_name(framework)

      notice =
        if use_inertia do
          """
          AshTypescript with #{name} + Inertia.js + #{bundler} installed!

          Next Steps:
          1. Start your Phoenix server: mix phx.server
          2. Visit http://localhost:4000/ash-typescript
          3. Configure your domain with the AshTypescript.Rpc extension

          Documentation: https://hexdocs.pm/ash_typescript
          Inertia.js: https://inertiajs.com
          """
        else
          """
          AshTypescript with #{name} + #{bundler} installed!

          Next Steps:
          1. Start your Phoenix server: mix phx.server
          2. Visit http://localhost:4000/ash-typescript
          3. Configure your domain with the AshTypescript.Rpc extension

          Documentation: https://hexdocs.pm/ash_typescript
          """
        end

      Igniter.add_notice(igniter, notice)
    end

    defp framework_display_name("react"), do: "React"
    defp framework_display_name("vue"), do: "Vue"
    defp framework_display_name("svelte"), do: "Svelte"
    defp framework_display_name("solid"), do: "SolidJS"
    defp framework_display_name(other), do: other
    
    defp preset_display_name("tanstack_db"), do: "TanStack DB"
    defp preset_display_name(other), do: other
    
    defp bundler_display_name("vite"), do: "Vite"
    defp bundler_display_name("esbuild"), do: "ESBuild"
    defp bundler_display_name(other), do: other
  end
else
  defmodule Mix.Tasks.Phx.Sync.TanstackDb.SetupLive2 do
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