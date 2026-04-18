# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule PhoenixSyncFix.Installer.PackageJson do
    @moduledoc false

    @doc """
    Ensure package.json exists and add framework- and preset-specific dependencies.
    For vite, creates an empty package.json only when missing (phoenix_vite manages Phoenix deps).
    For esbuild, starts with Phoenix deps.
    """
    def create_package_json(igniter, "vite", framework, preset) do
      igniter
      |> Igniter.create_or_update_file("assets/package.json", "{}\n", fn source -> source end)
      |> add_framework_deps(framework, "vite")
      |> add_preset_deps(preset, framework, "vite")
    end

    def create_package_json(igniter, _bundler, framework, preset) do
      base_package_json =
        %{
          "dependencies" => %{
            "phoenix" => "file:../deps/phoenix",
            "phoenix_html" => "file:../deps/phoenix_html",
            "phoenix_live_view" => "file:../deps/phoenix_live_view",
            "topbar" => "^3.0.0"
          }
        }
        |> encode_pretty_json()

      igniter
      |> Igniter.create_or_update_file("assets/package.json", base_package_json, fn source ->
        source
      end)
      |> add_framework_deps(framework, "esbuild")
      |> add_preset_deps(preset, framework, "esbuild")
      |> update_vendor_imports()
    end

    @doc "Add esbuild as an npm dependency (for plugin-based builds that bypass the Elixir esbuild wrapper)."
    def add_esbuild_npm_dep(igniter) do
      update_package_json(igniter, fn package_json ->
        merge_package_section(package_json, "devDependencies", %{"esbuild" => "^0.24.0"})
      end)
    end

    @doc "Update package.json by applying an updater function to the parsed JSON."
    def update_package_json(igniter, updater) do
      Igniter.update_file(igniter, "assets/package.json", fn source ->
        case Jason.decode(source.content) do
          {:ok, package_json} ->
            updated_package_json = updater.(package_json)

            if updated_package_json == package_json do
              source
            else
              Rewrite.Source.update(source, :content, encode_pretty_json(updated_package_json))
            end

          {:error, _error} ->
            source
        end
      end)
    end

    @doc "Merge deps into a section of package.json (dependencies or devDependencies)."
    def merge_package_section(package_json, section, deps) when is_map(deps) do
      current_deps = Map.get(package_json, section, %{})
      Map.put(package_json, section, Map.merge(current_deps, deps))
    end

    def encode_pretty_json(data) do
      Jason.encode!(data, pretty: true) <> "\n"
    end

    # -- Private --

    defp add_framework_deps(igniter, framework, bundler) do
      deps = get_framework_deps(framework, bundler)

      update_package_json(igniter, fn package_json ->
        package_json
        |> merge_package_section("dependencies", deps.dependencies)
        |> merge_package_section("devDependencies", deps.dev_dependencies)
      end)
    end

    defp add_preset_deps(igniter, preset, framework, bundler) do
      deps = get_preset_deps(preset, framework, bundler)

      update_package_json(igniter, fn package_json ->
        package_json
        |> merge_package_section("dependencies", deps.dependencies)
        |> merge_package_section("devDependencies", deps.dev_dependencies)
      end)
    end

    defp update_vendor_imports(igniter) do
      igniter
      |> Igniter.update_file("assets/js/app.js", fn source ->
        Rewrite.Source.update(source, :content, fn content ->
          String.replace(content, "../vendor/topbar", "topbar")
        end)
      end)
      |> delete_vendor_files()
    end

    defp delete_vendor_files(igniter) do
      igniter
      |> Igniter.rm("assets/vendor/topbar.js")
    end

    # Framework deps -- only the framework core + bundler plugin. No TanStack, Prism, DaisyUI.

    defp get_framework_deps("react", "vite") do
      %{
        dependencies: %{"react" => "^19.1.1", "react-dom" => "^19.1.1"},
        dev_dependencies: %{
          "@types/react" => "^19.1.13",
          "@types/react-dom" => "^19.1.9",
          "@vitejs/plugin-react" => "^4.5.0"
        }
      }
    end

    defp get_framework_deps("react", _bundler) do
      %{
        dependencies: %{"react" => "^19.1.1", "react-dom" => "^19.1.1"},
        dev_dependencies: %{
          "@types/react" => "^19.1.13",
          "@types/react-dom" => "^19.1.9"
        }
      }
    end

    defp get_framework_deps("vue", "vite") do
      %{
        dependencies: %{"vue" => "^3.5.16"},
        dev_dependencies: %{"@vitejs/plugin-vue" => "^5.2.4"}
      }
    end

    defp get_framework_deps("vue", _bundler) do
      %{
        dependencies: %{"vue" => "^3.5.16"},
        dev_dependencies: %{"esbuild-plugin-vue3" => "^0.4.2"}
      }
    end

    defp get_framework_deps("svelte", "vite") do
      %{
        dependencies: %{"svelte" => "^5.33.0"},
        dev_dependencies: %{"@sveltejs/vite-plugin-svelte" => "^5.0.3"}
      }
    end

    defp get_framework_deps("svelte", _bundler) do
      %{
        dependencies: %{"svelte" => "^5.33.0"},
        dev_dependencies: %{"esbuild-svelte" => "^0.9.3"}
      }
    end

    defp get_framework_deps("solid", "vite") do
      %{
        dependencies: %{"solid-js" => "^1.9.9"},
        dev_dependencies: %{"vite-plugin-solid" => "^2.11.9"}
      }
    end

    defp get_framework_deps("solid", _bundler) do
      %{
        dependencies: %{"solid-js" => "^1.9.9"},
        dev_dependencies: %{"esbuild-plugin-solid" => "^0.6.0"}
      }
    end

    defp get_framework_deps(_framework, _bundler) do
      %{dependencies: %{}, dev_dependencies: %{}}
    end

    # Preset deps -- only adds deps not already covered by framework and phoenix_vite defaults.

    # TanStack DB currently supported with React + Vite in task constraints.
    defp get_preset_deps("tanstack_db", "react", "vite") do
      %{
        dependencies: %{
          "@electric-sql/client" => "^1.0.10",
          "@tanstack/electric-db-collection" => "^0.1.18",
          "@tanstack/react-db" => "^0.1.16",
          "@tanstack/react-router" => "^1.131.35",
          "@tanstack/react-router-devtools" => "^1.131.35",
          "react-json-view-lite" => "^2.4.2",
          "zod" => "^4.1.5"
        },
        dev_dependencies: %{
          "@eslint/compat" => "^1.3.1",
          "@eslint/js" => "^9.32.0",
          "@tailwindcss/forms" => "^0.5.10",
          "@tanstack/router-plugin" => "^1.131.7",
          "@types/node" => "^24.2.1",
          "@typescript-eslint/eslint-plugin" => "^8.38.0",
          "@typescript-eslint/parser" => "^8.38.0",
          "eslint" => "^9.32.0",
          "eslint-config-prettier" => "^10.1.8",
          "eslint-plugin-prettier" => "^5.5.4",
          "eslint-plugin-react" => "^7.37.5",
          "prettier" => "^3.6.2",
          "typescript" => "^5.9.2"
        }
      }
    end

    # For unsupported combinations (or no preset), no-op.
    defp get_preset_deps("tanstack_db", _framework, _bundler) do
      %{dependencies: %{}, dev_dependencies: %{}}
    end

    defp get_preset_deps(nil, _framework, _bundler) do
      %{dependencies: %{}, dev_dependencies: %{}}
    end

    defp get_preset_deps(_preset, _framework, _bundler) do
      %{dependencies: %{}, dev_dependencies: %{}}
    end
  end
end