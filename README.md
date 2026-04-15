# PhoenixSyncFix

**TODO: Add description**

## Installation

### Igniter

```sh
# Fresh project
mix igniter.new my_app --with phx.new --install phoenix_sync_fix --sync-mode embedded
# Existing project
mix igniter.install phoenix_sync_fix --sync-mode embedded
```

### Manual

The package can be installed
by adding `phoenix_sync_fix` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:phoenix_sync_fix, "~> 0.1.0"}
  ]
end
```

Then:

```sh
mix deps.get
mix phoenix_sync_fix.install --sync-mode embedded
```
