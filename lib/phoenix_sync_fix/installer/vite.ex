# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(Igniter) do
  defmodule PhoenixSyncFix.Installer.Vite do
    @moduledoc false

    @type config_format :: :ts | :mjs

    @doc """
    Update whichever Vite config exists (`vite.config.ts` preferred, fallback to `vite.config.mjs`)
    with a shared template customized by framework + preset.

    If neither exists, it creates `assets/vite.config.mjs`.
    """
    @spec update_vite_config_with_framework(Igniter.t(), String.t() | nil, String.t() | nil) :: Igniter.t()
    def update_vite_config_with_framework(igniter, framework, preset) do
      case detect_vite_config_format(igniter) do
        :ts -> update_vite_config(igniter, framework, preset, :ts)
        :mjs -> update_vite_config(igniter, framework, preset, :mjs)
        :none -> update_vite_config(igniter, framework, preset, :mjs)
      end
    end

    @doc """
    Update a specific Vite config format (`:ts` or `:mjs`) using a shared template.

    Always writes a complete config file for deterministic output.
    """
    @spec update_vite_config(Igniter.t(), String.t() | nil, String.t() | nil, config_format()) :: Igniter.t()
    def update_vite_config(igniter, framework, preset, format) when format in [:ts, :mjs] do
      content = render_vite_config(format, framework, preset)
      write_vite_config(igniter, format, content)
    end

    @doc """
    Convert to `assets/vite.config.ts` using the same framework + preset template and remove `.mjs`.
    """
    @spec convert_vite_config_to_ts(Igniter.t(), String.t() | nil, String.t() | nil) :: Igniter.t()
    def convert_vite_config_to_ts(igniter, framework, preset) do
      igniter
      |> update_vite_config(framework, preset, :ts)
      |> Igniter.rm("assets/vite.config.mjs")
    end

    @doc """
    Convert to `assets/vite.config.mjs` using the same framework + preset template and remove `.ts`.
    """
    @spec convert_vite_config_to_mjs(Igniter.t(), String.t() | nil, String.t() | nil) :: Igniter.t()
    def convert_vite_config_to_mjs(igniter, framework, preset) do
      igniter
      |> update_vite_config(framework, preset, :mjs)
      |> Igniter.rm("assets/vite.config.ts")
    end

    @doc """
    Ensure the selected Vite config format exists and remove the other one.
    """
    @spec ensure_vite_config_format(Igniter.t(), config_format(), String.t() | nil, String.t() | nil) :: Igniter.t()
    def ensure_vite_config_format(igniter, :ts, framework, preset),
      do: convert_vite_config_to_ts(igniter, framework, preset)

    def ensure_vite_config_format(igniter, :mjs, framework, preset),
      do: convert_vite_config_to_mjs(igniter, framework, preset)

    @doc """
    Guard against a PhoenixVite bug where cache_static_manifest_latest in runtime.exs
    fails during MIX_ENV=prod assets.deploy because the manifest doesn't exist yet.
    """
    def maybe_fix_runtime_manifest_cache(igniter, "vite", app_name) do
      runtime_path = "config/runtime.exs"

      direct_call =
        "cache_static_manifest_latest: PhoenixVite.cache_static_manifest_latest(:#{app_name})"

      tuple_call =
        ~s|cache_static_manifest_latest: PhoenixVite.cache_static_manifest_latest({:#{app_name}, "priv/static/.vite/manifest.json"})|

      guarded_call =
        ~s|cache_static_manifest_latest: if(File.exists?(Application.app_dir(:#{app_name}, "priv/static/.vite/manifest.json")), do: PhoenixVite.cache_static_manifest_latest(:#{app_name}), else: %{})|

      Igniter.update_file(igniter, runtime_path, fn source ->
        content = source.content

        updated_content =
          content
          |> String.replace(direct_call, guarded_call)
          |> String.replace(tuple_call, guarded_call)

        if updated_content == content do
          source
        else
          Rewrite.Source.update(source, :content, updated_content)
        end
      end)
    end

    def maybe_fix_runtime_manifest_cache(igniter, _bundler, _app_name), do: igniter

    # -- Private --

    defp detect_vite_config_format(igniter) do
      ts = read_vite_config(igniter, "assets/vite.config.ts")
      mjs = read_vite_config(igniter, "assets/vite.config.mjs")

      cond do
        is_binary(ts) and String.trim(ts) != "" -> :ts
        is_binary(mjs) and String.trim(mjs) != "" -> :mjs
        true -> :none
      end
    end

    defp vite_config_path(:ts), do: "assets/vite.config.ts"
    defp vite_config_path(:mjs), do: "assets/vite.config.mjs"

    defp write_vite_config(igniter, format, content) do
      path = vite_config_path(format)

      Igniter.create_or_update_file(igniter, path, content, fn source ->
        if source.content == content do
          source
        else
          Rewrite.Source.update(source, :content, content)
        end
      end)
    end

    # Uses create_or_update_file as a portable way to get current content in Igniter flows.
    # If the file does not exist, this can create it with empty content; callers should treat
    # empty string as "missing".
    defp read_vite_config(igniter, path) do
      key = {__MODULE__, :read_vite_config, path}

      _igniter =
        Igniter.create_or_update_file(igniter, path, "", fn source ->
          Process.put(key, source.content)
          source
        end)

      case Process.get(key) do
        nil ->
          nil

        content ->
          Process.delete(key)
          content
      end
    end

    defp render_vite_config(format, framework, preset) do
      imports = imports_for(framework, preset) |> Enum.uniq()
      plugins = plugins_for(framework, preset) |> Enum.uniq()
      spa_entry = spa_entry_for(framework, preset)

      """
      import { defineConfig, loadEnv } from 'vite'
      #{Enum.join(imports, "\n")}

      export default defineConfig(({ mode }) => {
        const env = loadEnv(mode, process.cwd(), '')
        const isProd = mode === 'production'

        return {
          server: {
            port: 5173,
            strictPort: true,
            cors: { origin: "http://localhost:4000" },
          },
          optimizeDeps: {
            // https://vitejs.dev/guide/dep-pre-bundling#monorepos-and-linked-dependencies
            include: ["phoenix", "phoenix_html", "phoenix_live_view"],
          },
          build: {
            outDir: "../priv/static",
            target: ['es2022'],
            minify: isProd,
            sourcemap: !isProd,
            manifest: true,
            rollupOptions: {
              input: {
                liveview: "js/app.js",
                spa: "#{spa_entry}",
                css: "css/app.css",
              },
              output: {
                assetFileNames: 'assets/[name][extname]',
                chunkFileNames: 'assets/chunk/[name].js',
                entryFileNames: 'assets/[name].js',
              },
            },
            emptyOutDir: true,
          },
          // LV Colocated JS and Hooks
          // https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.ColocatedJS.html#module-internals
          resolve: {
            alias: {
              "@": ".",
              "phoenix-colocated": `${process.env.MIX_BUILD_PATH}/phoenix-colocated`,
            },
          },
          define: {
            __APP_ENV__: env.APP_ENV,
            'process.env.NODE_ENV': JSON.stringify(isProd ? 'production' : 'development'),
            'import.meta.env.PROD': isProd,
            'import.meta.env.DEV': !isProd,
          },
          plugins: [
#{plugins |> Enum.map(&indent_multiline(&1, 6)) |> Enum.join(",\n")}
          ]
        }
      });
      """
      |> maybe_render_as_mjs(format)
      |> Kernel.<>("\n")
    end

    defp maybe_render_as_mjs(content, :ts), do: content

    # The template is plain ESM-compatible JS already; this keeps output identical for .mjs.
    defp maybe_render_as_mjs(content, :mjs), do: content

    # -- Framework + preset matrices --

    defp imports_for("react", "tanstack_db") do
      [
        "import react from '@vitejs/plugin-react'",
        "import tailwindcss from '@tailwindcss/vite'",
        "import { tanstackRouter } from '@tanstack/router-plugin/vite'",
        "import { phoenixVitePlugin } from 'phoenix_vite'"
      ]
    end

    defp imports_for("react", nil) do
      [
        "import react from '@vitejs/plugin-react'",
        "import tailwindcss from '@tailwindcss/vite'",
        "import { phoenixVitePlugin } from 'phoenix_vite'"
      ]
    end

    defp imports_for("vue", nil) do
      [
        "import vue from '@vitejs/plugin-vue'",
        "import tailwindcss from '@tailwindcss/vite'",
        "import { phoenixVitePlugin } from 'phoenix_vite'"
      ]
    end

    defp imports_for("svelte", nil) do
      [
        "import { svelte } from '@sveltejs/vite-plugin-svelte'",
        "import tailwindcss from '@tailwindcss/vite'",
        "import { phoenixVitePlugin } from 'phoenix_vite'"
      ]
    end

    defp imports_for("solid", nil) do
      [
        "import solid from 'vite-plugin-solid'",
        "import tailwindcss from '@tailwindcss/vite'",
        "import { phoenixVitePlugin } from 'phoenix_vite'"
      ]
    end

    # Fallback for unknown combinations: keep phoenix + tailwind at minimum.
    defp imports_for(_framework, _preset) do
      [
        "import tailwindcss from '@tailwindcss/vite'",
        "import { phoenixVitePlugin } from 'phoenix_vite'"
      ]
    end

    defp plugins_for("react", "tanstack_db") do
      [
        """
        tanstackRouter({
          target: 'react',
          autoCodeSplitting: true,
          routesDirectory: "./js/routes",
          generatedRouteTree: "./js/routeTree.gen.ts",
        })
        """
        |> String.trim(),
        "react()",
        "tailwindcss()",
        phoenix_vite_plugin_call()
      ]
    end

    defp plugins_for("react", nil), do: ["react()", "tailwindcss()", phoenix_vite_plugin_call()]
    defp plugins_for("vue", nil), do: ["vue()", "tailwindcss()", phoenix_vite_plugin_call()]
    defp plugins_for("svelte", nil), do: ["svelte()", "tailwindcss()", phoenix_vite_plugin_call()]
    defp plugins_for("solid", nil), do: ["solid()", "tailwindcss()", phoenix_vite_plugin_call()]

    defp plugins_for(_framework, _preset), do: ["tailwindcss()", phoenix_vite_plugin_call()]

    defp spa_entry_for("vue", _preset), do: "js/index.ts"
    defp spa_entry_for("svelte", _preset), do: "js/index.ts"
    defp spa_entry_for("react", _preset), do: "js/index.tsx"
    defp spa_entry_for("solid", _preset), do: "js/index.tsx"
    defp spa_entry_for(_framework, _preset), do: "js/index.tsx"

    defp phoenix_vite_plugin_call do
      """
      phoenixVitePlugin({
        pattern: /\\.(ex|heex)$/
      })
      """
      |> String.trim()
    end

    defp indent_multiline(text, spaces) do
      prefix = String.duplicate(" ", spaces)

      text
      |> String.split("\n")
      |> Enum.map_join("\n", fn line -> prefix <> line end)
    end
  end
end