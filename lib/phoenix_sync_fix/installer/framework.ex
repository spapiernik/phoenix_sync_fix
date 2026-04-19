# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule PhoenixSyncFix.Installer.Framework do
    @moduledoc false

    @valid_frameworks ["react", "vue", "svelte", "solid"]
    @valid_bundlers ["vite", "esbuild"]
    @valid_presets ["tanstack_db"]

    def validate_framework(igniter, nil), do: igniter
    def validate_framework(igniter, f) when f in @valid_frameworks, do: igniter

    def validate_framework(igniter, invalid) do
      Igniter.add_issue(
        igniter,
        "Invalid framework '#{invalid}'. Supported: #{Enum.join(@valid_frameworks, ", ")}"
      )
    end

    def validate_preset(igniter, nil), do: igniter
    def validate_preset(igniter, p) when p in @valid_presets, do: igniter

    def validate_preset(igniter, invalid) do
      Igniter.add_issue(
        igniter,
        "Invalid preset '#{invalid}'. Supported: #{Enum.join(@valid_presets, ", ")}"
      )
    end

    def validate_bundler(igniter, nil), do: igniter
    def validate_bundler(igniter, b) when b in @valid_bundlers, do: igniter

    def validate_bundler(igniter, invalid) do
      Igniter.add_issue(
        igniter,
        "Invalid bundler '#{invalid}'. Supported: #{Enum.join(@valid_bundlers, ", ")}"
      )
    end

    alias PhoenixSynFix.Installer.LandingPage

    @tanstack_template_subdir "igniter/phx.sync.tanstack_db"

    @doc "Create the framework's entry point file (index.tsx / index.ts + App component)."
    def create_index_page(igniter, "react", "tanstack_db") do
      content = """
      import { StrictMode } from "react";
      import ReactDOM from "react-dom/client";
      import { RouterProvider, createRouter } from "@tanstack/react-router";

      import { routeTree } from "./routeTree.gen";

      const router = createRouter({ routeTree });

      declare module "@tanstack/react-router" {
        interface Register {
          router: typeof router
        }
      }

      const rootElement = document.getElementById("app")!
      if (!rootElement.innerHTML) {
        const root = ReactDOM.createRoot(rootElement)
        root.render(
          <StrictMode>
            <RouterProvider router={router} />
          </StrictMode>,
        )
      }
      """

      igniter
      |> Igniter.create_new_file("assets/js/index.tsx", content, on_exists: :warning)
      |> install_tanstack_db_assets()
    end

    def create_index_page(igniter, "react", nil) do
      page_body = LandingPage.page_jsx()

      content = """
      import React, { useEffect } from "react";
      import { createRoot } from "react-dom/client";
      import { initLandingPage } from "./animation";

      function App() {
        useEffect(() => {
          const el = document.getElementById("animation-container");
          if (el) return initLandingPage(el);
        }, []);

        return (
      #{page_body}
        );
      }

      createRoot(document.getElementById("app")!).render(
        <React.StrictMode>
          <App />
        </React.StrictMode>,
      );
      """

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/index.tsx", content, on_exists: :warning)
    end

    def create_index_page(igniter, "vue", nil) do
      {script_content, template_content} = LandingPage.page_vue()
      vue_component = script_content <> "\n" <> template_content

      vue_index = """
      import { createApp } from "vue";
      import App from "./App.vue";

      createApp(App).mount("#app");
      """

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/App.vue", vue_component, on_exists: :warning)
      |> Igniter.create_new_file("assets/js/index.ts", vue_index, on_exists: :warning)
    end

    def create_index_page(igniter, "svelte", nil) do
      {script_content, template_content} = LandingPage.page_svelte()
      svelte_component = script_content <> "\n" <> template_content

      svelte_index = """
      import App from "./App.svelte";
      import { mount } from "svelte";

      mount(App, { target: document.getElementById("app")! });
      """

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/App.svelte", svelte_component, on_exists: :warning)
      |> Igniter.create_new_file("assets/js/index.ts", svelte_index, on_exists: :warning)
    end

    def create_index_page(igniter, "solid", nil) do
      page_body = LandingPage.page_jsx()

      content = """
      import { onMount, onCleanup } from "solid-js";
      import { render } from "solid-js/web";
      import { initLandingPage } from "./animation";

      function App() {
        onMount(() => {
          const el = document.getElementById("animation-container");
          if (el) {
            const cleanup = initLandingPage(el);
            onCleanup(cleanup);
          }
        });

        return (
      #{page_body}
        );
      }

      render(() => <App />, document.getElementById("app")!);
      """

      igniter
      |> write_animation_module()
      |> Igniter.create_new_file("assets/js/index.tsx", content, on_exists: :warning)
    end

    defp write_animation_module(igniter) do
      Igniter.create_new_file(
        igniter,
        "assets/js/animation.ts",
        LandingPage.animation_module(),
        on_exists: :warning
      )
    end

    @doc """
    Update tsconfig files in a preset-aware way.

    Current support:
    - "tanstack_db" + "vite": split tsconfig into root references + app + node configs.
    - any other preset/bundler: update/create a single assets/tsconfig.json.
    """
    def update_tsconfig(igniter, framework, preset, bundler) do
      case {preset, bundler} do
        {"tanstack_db", "vite"} ->
          update_tsconfig_split_for_tanstack_db(igniter, framework)

        _ ->
          update_single_tsconfig(igniter, framework)
      end
    end

    # -- Preset-specific strategy: TanStack DB on Vite --

    defp update_tsconfig_split_for_tanstack_db(igniter, framework) do
      root_existing = read_json_file(igniter, "assets/tsconfig.json")
      app_existing = read_json_file(igniter, "assets/tsconfig.app.json")
      node_existing = read_json_file(igniter, "assets/tsconfig.node.json")

      {root_seed, app_seed, node_seed} =
        derive_split_tsconfig_seeds(root_existing, app_existing, node_existing)

      root_target =
        root_seed
        |> deep_merge(split_root_defaults())
        |> ensure_reference_paths(["./tsconfig.app.json", "./tsconfig.node.json"])
        |> cleanup_root_for_split()

      app_target =
        app_seed
        |> deep_merge(split_app_defaults())
        |> deep_merge(split_framework_overrides(framework))
        |> ensure_include("js/**/*")
        |> ensure_paths_alias()

      node_target =
        node_seed
        |> deep_merge(split_node_defaults())
        |> ensure_include("vite.config.ts")
        |> ensure_paths_alias()

      igniter
      |> write_json_file("assets/tsconfig.json", root_target)
      |> write_json_file("assets/tsconfig.app.json", app_target)
      |> write_json_file("assets/tsconfig.node.json", node_target)
    end

    defp split_root_defaults do
      %{
        "files" => [],
        "references" => []
      }
    end

    defp split_app_defaults do
      %{
        "compilerOptions" => %{
          "tsBuildInfoFile" => "./node_modules/.tmp/tsconfig.app.tsbuildinfo",
          "target" => "ES2022",
          "useDefineForClassFields" => true,
          "lib" => ["ES2022", "DOM", "DOM.Iterable"],
          "module" => "ESNext",
          "skipLibCheck" => true,
          "moduleResolution" => "bundler",
          "allowImportingTsExtensions" => true,
          "isolatedModules" => true,
          "moduleDetection" => "force",
          "noEmit" => true,
          "strict" => true,
          "noUnusedLocals" => true,
          "noUnusedParameters" => true,
          "noFallthroughCasesInSwitch" => true,
          "noUncheckedSideEffectImports" => true
        }
      }
    end

    defp split_node_defaults do
      %{
        "compilerOptions" => %{
          "tsBuildInfoFile" => "./node_modules/.tmp/tsconfig.node.tsbuildinfo",
          "target" => "ES2022",
          "lib" => ["ES2023"],
          "module" => "ESNext",
          "skipLibCheck" => true,
          "moduleResolution" => "bundler",
          "allowImportingTsExtensions" => true,
          "isolatedModules" => true,
          "moduleDetection" => "force",
          "noEmit" => true,
          "strict" => true,
          "noUnusedLocals" => true,
          "noUnusedParameters" => true,
          "noFallthroughCasesInSwitch" => true,
          "noUncheckedSideEffectImports" => true
        }
      }
    end

    defp split_framework_overrides("react"),
      do: %{"compilerOptions" => %{"jsx" => "react-jsx"}}

    defp split_framework_overrides("solid"),
      do: %{"compilerOptions" => %{"jsx" => "preserve", "jsxImportSource" => "solid-js"}}

    defp split_framework_overrides(_), do: %{}

    defp derive_split_tsconfig_seeds(root_existing, app_existing, node_existing) do
      has_split? = is_map(app_existing) or is_map(node_existing)

      cond do
        has_split? ->
          {
            normalize_json_map(root_existing),
            normalize_json_map(app_existing),
            normalize_json_map(node_existing)
          }

        is_map(root_existing) ->
          root_map = normalize_json_map(root_existing)
          root_compiler = normalize_json_map(Map.get(root_map, "compilerOptions"))
          root_include = normalize_json_list(Map.get(root_map, "include"))

          app_seed =
            root_map
            |> Map.drop(["files", "references"])
            |> Map.put("compilerOptions", root_compiler)
            |> Map.put("include", root_include)

          node_seed = %{"compilerOptions" => root_compiler}

          {%{}, app_seed, node_seed}

        true ->
          {%{}, %{}, %{}}
      end
    end

    defp cleanup_root_for_split(root_config) do
      root_config
      |> Map.delete("compilerOptions")
      |> Map.delete("include")
      |> Map.delete("exclude")
      |> Map.delete("extends")
    end

    # -- Generic strategy: single tsconfig.json --

    defp update_single_tsconfig(igniter, framework) do
      existing = read_json_file(igniter, "assets/tsconfig.json")

      target =
        existing
        |> normalize_json_map()
        |> deep_merge(single_tsconfig_defaults())
        |> deep_merge(single_framework_overrides(framework))
        |> ensure_include("js/**/*")
        |> ensure_paths_alias()

      igniter
      |> write_json_file("assets/tsconfig.json", target)
    end

    defp single_tsconfig_defaults do
      %{
        "compilerOptions" => %{
          "baseUrl" => ".",
          "allowJs" => true,
          "noEmit" => true,
          "esModuleInterop" => true
        }
      }
    end

    defp single_framework_overrides("react"),
      do: %{"compilerOptions" => %{"jsx" => "react-jsx"}}

    defp single_framework_overrides("solid"),
      do: %{"compilerOptions" => %{"jsx" => "preserve", "jsxImportSource" => "solid-js"}}

    defp single_framework_overrides(_), do: %{}

    # -- JSON helpers --

    defp read_json_file(igniter, path) do
      result = {:missing, nil}

      result =
        Igniter.create_or_update_file(igniter, path, "", fn source ->
          parsed =
            case Jason.decode(source.content) do
              {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
              _ -> :invalid
            end

          Process.put({__MODULE__, :json_read_result, path}, parsed)
          source
        end)

      case result do
        _ ->
          case Process.get({__MODULE__, :json_read_result, path}) do
            {:ok, map} ->
              Process.delete({__MODULE__, :json_read_result, path})
              map

            _ ->
              Process.delete({__MODULE__, :json_read_result, path})
              nil
          end
      end
    end

    defp write_json_file(igniter, path, data) when is_map(data) do
      content = Jason.encode!(data, pretty: true) <> "\n"

      Igniter.create_or_update_file(igniter, path, content, fn source ->
        if source.content == content do
          source
        else
          Rewrite.Source.update(source, :content, content)
        end
      end)
    end

    defp ensure_paths_alias(config) do
      compiler_options = normalize_json_map(Map.get(config, "compilerOptions"))
      current_paths = normalize_json_map(Map.get(compiler_options, "paths"))
      updated_paths = Map.put_new(current_paths, "*", ["../deps/*"])
      Map.put(config, "compilerOptions", Map.put(compiler_options, "paths", updated_paths))
    end

    defp ensure_include(config, entry) do
      include = normalize_json_list(Map.get(config, "include"))

      updated_include =
        if entry in include do
          include
        else
          include ++ [entry]
        end

      Map.put(config, "include", updated_include)
    end

    defp ensure_reference_paths(config, required_paths) do
      existing_refs = normalize_json_list(Map.get(config, "references"))
      existing_paths = Enum.map(existing_refs, &reference_path/1)

      missing_refs =
        required_paths
        |> Enum.reject(&(&1 in existing_paths))
        |> Enum.map(fn path -> %{"path" => path} end)

      Map.put(config, "references", existing_refs ++ missing_refs)
    end

    defp reference_path(%{"path" => path}) when is_binary(path), do: path
    defp reference_path(_), do: nil

    defp normalize_json_map(value) when is_map(value), do: value
    defp normalize_json_map(_), do: %{}

    defp normalize_json_list(value) when is_list(value), do: value
    defp normalize_json_list(_), do: []

    defp deep_merge(left, right) when is_map(left) and is_map(right) do
      Map.merge(left, right, fn _key, left_value, right_value ->
        deep_merge(left_value, right_value)
      end)
    end

    defp deep_merge(_left, right), do: right

    # -- Preset asset installers --

    defp install_tanstack_db_assets(igniter) do
      sync_mode = detect_phoenix_sync_mode()

      igniter
      |> copy_file_from_template(
        template_path("assets/js/api.ts.eex"),
        "assets/js/api.ts"
      )
      |> copy_file_from_template(
        template_path("assets/js/routeTree.gen.ts.eex"),
        "assets/js/routeTree.gen.ts"
      )
      |> copy_directory_from_template(
        template_path("assets/js/components"),
        "assets/js/components"
      )
      |> copy_directory_from_template(
        template_path("assets/js/db"),
        "assets/js/db"
      )
      |> copy_directory_from_template(
        template_path("assets/js/routes"),
        "assets/js/routes"
      )
      |> copy_compose_yaml(sync_mode)
    end

    defp detect_phoenix_sync_mode do
      case Application.get_env(:phoenix_sync, :mode) do
        :http -> :http
        :embedded -> :embedded
        _ -> :embedded
      end
    end

    defp copy_compose_yaml(igniter, :http) do
      app_name = Igniter.Project.Application.app_name(igniter)

      rendered =
        template_path("compose.http.yaml.eex")
        |> EEx.eval_file(app_name: app_name)

      Igniter.create_or_update_file(igniter, "compose.yaml", rendered <> "\n", fn _source ->
        Rewrite.Source.from_string!(rendered <> "\n", "compose.yaml")
      end)
    end

    defp copy_compose_yaml(igniter, _mode) do
      app_name = Igniter.Project.Application.app_name(igniter)

      rendered =
        template_path("compose.embedded.yaml.eex")
        |> EEx.eval_file(app_name: app_name)

      Igniter.create_or_update_file(igniter, "compose.yaml", rendered <> "\n", fn _source ->
        Rewrite.Source.from_string!(rendered <> "\n", "compose.yaml")
      end)
    end

    defp copy_file_from_template(igniter, source_path, destination_path) do
      content = File.read!(source_path)

      Igniter.create_or_update_file(igniter, destination_path, content, fn source ->
        if source.content == content do
          source
        else
          Rewrite.Source.update(source, :content, content)
        end
      end)
    end

    defp copy_directory_from_template(igniter, source_dir, destination_dir) do
      source_dir
      |> list_files_recursively()
      |> Enum.reduce(igniter, fn source_file, acc ->
        relative_path = Path.relative_to(source_file, source_dir)
        destination_path = Path.join(destination_dir, relative_path)
        copy_file_from_template(acc, source_file, destination_path)
      end)
    end

    defp list_files_recursively(dir) do
      dir
      |> File.ls!()
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.flat_map(fn path ->
        if File.dir?(path) do
          list_files_recursively(path)
        else
          [path]
        end
      end)
    end

    defp template_path(relative_path) do
      Path.join([priv_dir!(), @tanstack_template_subdir, relative_path])
    end

    defp priv_dir! do
      case :code.priv_dir(:phoenix_sync_fix) do
        dir when is_list(dir) -> List.to_string(dir)
        _ -> raise "Could not resolve :phoenix_sync_fix priv directory"
      end
    end
  end
end