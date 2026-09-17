use std::sync::Arc;
use clap::{Parser, Subcommand};
use tracing::{info, Level};
use tracing_subscriber::FmtSubscriber;

use airflow_core::arbitration::ArbitrationEngine;
use airflow_core::drivers::ShokzDriver;
use airflow_core::models::{AppConfig, EngineState, PairedDeviceInfo};
use airflow_core::whitelist::DeviceWhitelistManager;

#[derive(Parser, Debug)]
#[command(name = "airflow")]
#[command(about = "Universal cross-platform wireless headphone handoff daemon & CLI", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Run the background handoff arbitration daemon
    Daemon {
        #[arg(long, default_value = "Wireless Headphone")]
        target_headphone: String,
        #[arg(long)]
        target_phone: Option<String>,
        #[arg(long, default_value_t = 1500)]
        cooldown_ms: u64,
    },
    /// Show current whitelist binding
    WhitelistShow,
    /// Bind a mobile device to the whitelist
    WhitelistBind {
        #[arg(long)]
        id: String,
        #[arg(long)]
        name: String,
        #[arg(long)]
        addr: Option<String>,
    },
    /// Unbind any active mobile device from whitelist
    WhitelistUnbind,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let subscriber = FmtSubscriber::builder()
        .with_max_level(Level::INFO)
        .finish();
    tracing::subscriber::set_global_default(subscriber)?;

    let cli = Cli::parse();
    let command = cli.command.unwrap_or(Commands::Daemon {
        target_headphone: "Wireless Headphone".to_string(),
        target_phone: None,
        cooldown_ms: 1500,
    });

    match command {
        Commands::Daemon {
            target_headphone,
            target_phone,
            cooldown_ms,
        } => {
            info!("Starting AirFlow arbitration engine (Rust Core)...");
            let mut config = AppConfig::default();
            config.target_headphone_name = target_headphone;
            config.target_phone_name = target_phone;
            config.arbitration_cooldown_ms = cooldown_ms;

            let driver = Arc::new(ShokzDriver::default());
            let whitelist = Arc::new(DeviceWhitelistManager::new(config.clone()));
            let engine = Arc::new(ArbitrationEngine::new(driver, whitelist.clone(), config));

            engine.on_state_changed(|state| match state {
                EngineState::Idle => info!("[Engine] State -> Idle"),
                EngineState::Bypassed { reason } => {
                    info!("[Engine] State -> Bypassed ({})", reason)
                }
                EngineState::HostActive => info!("[Engine] State -> HostActive (Playing)"),
                EngineState::PeerActive => info!("[Engine] State -> PeerActive"),
                EngineState::Cooldown { remaining_ms } => {
                    info!("[Engine] State -> Cooldown ({}ms)", remaining_ms)
                }
            });

            engine.on_remote_pause_requested(|peer| {
                info!(
                    "[Handoff] Remote pause requested for whitelisted peer '{}' ({})",
                    peer.name, peer.id
                );
            });

            info!("AirFlow Engine initialized and ready. Press Ctrl+C to terminate.");
            tokio::signal::ctrl_c().await?;
            info!("Shutting down AirFlow daemon.");
        }
        Commands::WhitelistShow => {
            let config = AppConfig::default();
            let whitelist = DeviceWhitelistManager::new(config);
            if let Some(peer) = whitelist.get_bound_device() {
                println!("Whitelisted Device: {} ({})", peer.name, peer.id);
            } else {
                println!("No mobile device currently bound.");
            }
        }
        Commands::WhitelistBind { id, name, addr } => {
            let config = AppConfig::default();
            let whitelist = DeviceWhitelistManager::new(config);
            let peer = PairedDeviceInfo::new(id, name.clone(), addr, true);
            whitelist.bind_device(peer);
            println!("Successfully bound device '{}' to whitelist.", name);
        }
        Commands::WhitelistUnbind => {
            let config = AppConfig::default();
            let whitelist = DeviceWhitelistManager::new(config);
            whitelist.unbind_device();
            println!("Unbound device from whitelist.");
        }
    }

    Ok(())
}
