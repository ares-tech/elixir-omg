# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :omg_watcher,
  namespace: OMG.Watcher,
  ecto_repos: [OMG.Watcher.DB.Repo],
  # an hour worth of blocks - this is how long the child chain server has to block spends from exiting utxos
  exit_processor_sla_margin: 4 * 60,
  maximum_block_withholding_time_ms: 1_200_000,
  block_getter_height_sync_interval_ms: 2_000,
  maximum_number_of_unapplied_blocks: 50,
  exit_processor_validation_interval_ms: 5_000,
  exit_finality_margin: 12,
  block_reorg_margin: 20,
  convenience_api_mode: false,
  child_chain_url: "http://localhost:9656"

# Configures the endpoint
config :omg_watcher, OMG.Watcher.Web.Endpoint,
  secret_key_base: "grt5Ef/y/jpx7AfLmrlUS/nfYJUOq+2e+1xmU4nphTm2x8WB7nLFCJ91atbSBrv5",
  render_errors: [view: OMG.Watcher.Web.View.ErrorView, accepts: ~w(json)],
  pubsub: [name: OMG.Watcher.PubSub, adapter: Phoenix.PubSub.PG2]

config :omg_watcher, :phoenix_swagger,
  swagger_files: %{
    "priv/static/swagger.json" => [router: OMG.Watcher.Web.Router]
  }

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
