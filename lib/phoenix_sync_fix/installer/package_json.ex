# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
# SPDX-FileCopyrightText: 2026 Santiago Papiernik <https://github.com/spapiernik/phoenix_sync_fix/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule PhoenixSyncFix.Installer.PackageJson do
    @moduledoc false

    @doc """
    Ensure package.json exists and add framework- and preset-specific dependencies.
    For vite, creates an empty package.json only when missing (phoenix_vite manages Phoenix deps).
    """
    def create_package_json(igniter, "vite", framework, preset) do
      igniter
      |> Igniter.create_or_update_file("assets/package.json", "{}\n", fn source -> source end)
      |> add_package_metadata_and_scripts("vite")
      |> add_framework_deps(framework, "vite")
      |> add_preset_deps(preset, framework, "vite")
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
      data
      |> ordered_root_entries()
      |> encode_pretty_ordered_root()
      |> Kernel.<>("\n")
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

    defp add_package_metadata_and_scripts(igniter, bundler) do
      update_package_json(igniter, fn package_json ->
        app_name = infer_app_name(igniter, package_json)

        package_json
        |> Map.put_new("name", app_name)
        |> Map.put_new("version", "0.0.0")
        |> Map.put_new("type", "module")
        |> merge_scripts(default_scripts(bundler))
      end)
    end

    defp merge_scripts(package_json, scripts_to_add) when is_map(scripts_to_add) do
      current_scripts = Map.get(package_json, "scripts", %{})
      Map.put(package_json, "scripts", Map.merge(scripts_to_add, current_scripts))
    end

    defp default_scripts("vite") do
      %{
        "build" => "tsc -b && vite build --mode development",
        "build:only" => "vite build --mode development",
        "build:prod" => "vite build --mode production",
        "dev" => "vite",
        "format" => "prettier --write \"**/*.{ts,tsx,js,jsx,json,css,md}\"",
        "format:check" => "prettier --check \"**/*.{ts,tsx,js,jsx,json,css,md}\"",
        "lint" => "eslint .",
        "preview" => "vite preview",
        "typecheck" => "tsc -b"
      }
    end

    defp default_scripts(_bundler) do
      %{
        "build" => "tsc -b",
        "dev" => "mix phx.server",
        "format" => "prettier --write \"**/*.{ts,tsx,js,jsx,json,css,md}\"",
        "format:check" => "prettier --check \"**/*.{ts,tsx,js,jsx,json,css,md}\"",
        "lint" => "eslint .",
        "typecheck" => "tsc -b"
      }
    end

    defp infer_app_name(igniter, package_json) do
      Map.get(package_json, "name") || app_name_from_igniter(igniter) || "app"
    end

    defp app_name_from_igniter(igniter) do
      cond do
        is_map(igniter) and Map.has_key?(igniter, :assigns) ->
          assigns = Map.get(igniter, :assigns, %{})

          cond do
            is_map(assigns) and is_binary(Map.get(assigns, :app_name)) ->
              Map.get(assigns, :app_name)

            is_map(assigns) and is_binary(Map.get(assigns, "app_name")) ->
              Map.get(assigns, "app_name")

            true ->
              nil
          end

        true ->
          nil
      end
    end

    defp ordered_root_entries(package_json) when is_map(package_json) do
      canonical_keys = [
        "name",
        "version",
        "type",
        "scripts",
        "dependencies",
        "devDependencies"
      ]

      canonical_entries =
        canonical_keys
        |> Enum.reduce([], fn key, acc ->
          case Map.fetch(package_json, key) do
            {:ok, value} -> [{key, value} | acc]
            :error -> acc
          end
        end)
        |> Enum.reverse()

      extra_entries =
        package_json
        |> Enum.reject(fn {key, _value} -> key in canonical_keys end)
        |> Enum.sort_by(fn {key, _value} -> key end)

      canonical_entries ++ extra_entries
    end

    defp ordered_root_entries(other), do: other

    defp encode_pretty_ordered_root(entries) when is_list(entries) do
      body =
        entries
        |> Enum.map(fn {key, value} ->
          encoded_value =
            value
            |> Jason.encode!(pretty: true)
            |> indent_multiline_json(2)

          "  " <> Jason.encode!(key) <> ": " <> encoded_value
        end)
        |> Enum.join(",\n")

      "{\n" <> body <> "\n}"
    end
    
    defp encode_pretty_ordered_root(other), do: Jason.encode!(other, pretty: true)

    defp indent_multiline_json(json, spaces) when is_binary(json) and is_integer(spaces) and spaces >= 0 do
      indent = String.duplicate(" ", spaces)

      json
      |> String.split("\n")
      |> Enum.with_index()
      |> Enum.map(fn
        {line, 0} -> line
        {line, _idx} -> indent <> line
      end)
      |> Enum.join("\n")
    end

    defp add_preset_deps(igniter, preset, framework, bundler) do
      deps = get_preset_deps(preset, framework, bundler)

      update_package_json(igniter, fn package_json ->
        package_json
        |> merge_package_section("dependencies", deps.dependencies)
        |> merge_package_section("devDependencies", deps.dev_dependencies)
      end)
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

    defp get_framework_deps("vue", "vite") do
      %{
        dependencies: %{"vue" => "^3.5.16"},
        dev_dependencies: %{"@vitejs/plugin-vue" => "^5.2.4"}
      }
    end

    defp get_framework_deps("svelte", "vite") do
      %{
        dependencies: %{"svelte" => "^5.33.0"},
        dev_dependencies: %{"@sveltejs/vite-plugin-svelte" => "^5.0.3"}
      }
    end

    defp get_framework_deps("solid", "vite") do
      %{
        dependencies: %{"solid-js" => "^1.9.9"},
        dev_dependencies: %{"vite-plugin-solid" => "^2.11.9"}
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