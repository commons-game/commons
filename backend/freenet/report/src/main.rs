/// freeland-report — CLI tool for reading Freeland error telemetry from a Freenet error contract.
///
/// Connects to a Freenet node WebSocket, GETs the error contract, and prints
/// a formatted table of crash/error reports. Supports filtering and raw JSON output.
use std::{path::PathBuf, sync::Arc};

use anyhow::Context;
use chrono::{DateTime, TimeZone, Utc};
use clap::Parser;
use freenet_stdlib::{
    client_api::{ClientRequest, ContractRequest, ContractResponse, HostResponse, WebApi},
    prelude::{ContractContainer, ContractInstanceId, Parameters},
};
use freeland_error_contract::ErrorContractState;

// ---------------------------------------------------------------------------
// CLI arguments
// ---------------------------------------------------------------------------

#[derive(Parser, Debug)]
#[command(
    name = "freeland-report",
    about = "Read Freeland error telemetry from a Freenet error contract"
)]
struct Args {
    /// Freenet node WebSocket URL
    #[arg(
        long,
        default_value = "ws://[::1]:7509/v1/contract/command?encodingProtocol=native"
    )]
    node: String,

    /// Path to the freeland_error_contract package file
    #[arg(long)]
    contract: Option<PathBuf>,

    /// Only show reports newer than N seconds ago
    #[arg(long)]
    since: Option<f64>,

    /// Filter by error_type (e.g. webrtc_timeout)
    #[arg(long, name = "type")]
    error_type: Option<String>,

    /// Filter by phase
    #[arg(long)]
    phase: Option<String>,

    /// Output raw JSON instead of formatted table
    #[arg(long)]
    json: bool,
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    // Resolve contract path: flag > relative to CWD > relative to binary location.
    let contract_path = resolve_contract_path(args.contract)?;

    // Read the contract WASM/package bytes.
    let contract_bytes = std::fs::read(&contract_path).with_context(|| {
        format!(
            "Failed to read error contract from {}.\n\
             Build it with: cd contracts/error-contract && \
             CARGO_TARGET_DIR=../../target fdev build",
            contract_path.display()
        )
    })?;

    // Connect to Freenet node.
    let (node_ws, _) = tokio_tungstenite::connect_async(&args.node)
        .await
        .with_context(|| format!("Failed to connect to Freenet node at {}", args.node))?;

    let mut freenet = WebApi::start(node_ws);

    // Build container with empty parameters (single global instance).
    let params = Arc::new(Parameters::from(vec![]));
    let container = ContractContainer::try_from((contract_bytes, params))
        .map_err(|e| anyhow::anyhow!("Error contract init failed: {e}"))?;
    let contract_id: ContractInstanceId = container.id().clone();

    // Send GET request.
    let get = ClientRequest::ContractOp(ContractRequest::Get {
        key: contract_id,
        return_contract_code: false,
        subscribe: false,
        blocking_subscribe: false,
    });

    freenet
        .send(get)
        .await
        .context("Failed to send GET request to Freenet node")?;

    // Await response.
    let state_json = match freenet.recv().await {
        Ok(HostResponse::ContractResponse(ContractResponse::GetResponse { state, .. })) => {
            match std::str::from_utf8(state.as_ref()) {
                Ok(s) => s.to_string(),
                Err(_) => anyhow::bail!("Contract state is not valid UTF-8"),
            }
        }
        Ok(HostResponse::ContractResponse(ContractResponse::NotFound { .. })) => {
            println!("No error reports found (contract not yet created).");
            return Ok(());
        }
        Ok(other) => {
            anyhow::bail!("Unexpected response from Freenet node: {other:?}");
        }
        Err(e) => {
            let msg = e.to_string();
            if msg.contains("missing contract") {
                println!("No error reports found (contract not yet created).");
                return Ok(());
            }
            anyhow::bail!("Freenet node error: {e}");
        }
    };

    // Parse state.
    let contract_state: ErrorContractState =
        serde_json::from_str(&state_json).context("Failed to parse ErrorContractState")?;

    let now_secs = Utc::now().timestamp() as f64;

    // Apply filters.
    let mut reports: Vec<(&String, &freeland_error_contract::ErrorReport)> = contract_state
        .reports
        .iter()
        .filter(|(_, r)| {
            // --since filter
            if let Some(secs) = args.since {
                if now_secs - r.ts > secs {
                    return false;
                }
            }
            // --type filter
            if let Some(ref t) = args.error_type {
                if &r.error_type != t {
                    return false;
                }
            }
            // --phase filter
            if let Some(ref p) = args.phase {
                if &r.phase != p {
                    return false;
                }
            }
            true
        })
        .collect();

    let total = contract_state.reports.len();
    let filtered = reports.len();

    if args.json {
        // Raw JSON output: emit only the filtered reports.
        let filtered_map: serde_json::Map<String, serde_json::Value> = reports
            .iter()
            .map(|(k, v)| {
                (
                    (*k).clone(),
                    serde_json::to_value(v).unwrap_or(serde_json::Value::Null),
                )
            })
            .collect();
        let output = serde_json::json!({ "reports": filtered_map });
        println!("{}", serde_json::to_string_pretty(&output)?);
        return Ok(());
    }

    if filtered == 0 {
        println!("No reports found.");
        return Ok(());
    }

    // Sort by ts descending (newest first).
    reports.sort_by(|a, b| b.1.ts.partial_cmp(&a.1.ts).unwrap_or(std::cmp::Ordering::Equal));

    // Print header.
    let sep = "─".repeat(78);
    println!(
        "Freeland Error Reports  ({total} total, {filtered} filtered)"
    );
    println!("{sep}");
    println!(
        "{:<20} {:<20} {:<30} {:<9} {:<10} {}",
        "TIME", "TYPE", "FILE", "PHASE", "PLATFORM", "VER"
    );

    for (_, report) in &reports {
        let dt: DateTime<Utc> = Utc.timestamp_opt(report.ts as i64, 0).single()
            .unwrap_or_else(Utc::now);
        let time_str = dt.format("%Y-%m-%d %H:%M:%S").to_string();

        let file_display = truncate_path(&report.file, report.line);
        let platform_short = truncate_str(&report.platform, 10);
        let type_short = truncate_str(&report.error_type, 20);
        let phase_short = truncate_str(&report.phase, 9);

        println!(
            "{:<20} {:<20} {:<30} {:<9} {:<10} {}",
            time_str, type_short, file_display, phase_short, platform_short, report.game_version
        );
    }

    println!("{sep}");

    Ok(())
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Truncate a file path to "last_component.ext:line" (at most two components).
fn truncate_path(path: &str, line: i32) -> String {
    let components: Vec<&str> = path.split('/').collect();
    let short = if components.len() >= 2 {
        format!(
            "{}/{}",
            components[components.len() - 2],
            components[components.len() - 1]
        )
    } else {
        path.to_string()
    };
    format!("{short}:{line}")
}

/// Truncate a string to at most `max` characters, appending "…" if truncated.
fn truncate_str(s: &str, max: usize) -> String {
    if s.len() <= max {
        s.to_string()
    } else {
        format!("{}…", &s[..max.saturating_sub(1)])
    }
}

/// Resolve the contract path from an optional CLI override, falling back to
/// well-known relative locations from the current working directory.
fn resolve_contract_path(override_path: Option<PathBuf>) -> anyhow::Result<PathBuf> {
    if let Some(p) = override_path {
        return Ok(p);
    }

    // Candidates relative to cwd (the repo root when invoked via `cargo run`
    // or from the repo root directly).
    let candidates = [
        PathBuf::from(
            "backend/freenet/contracts/error-contract/build/freenet/freeland_error_contract",
        ),
        // Also try relative to the binary's directory (useful when installed).
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.join("freeland_error_contract")))
            .unwrap_or_default(),
    ];

    for candidate in &candidates {
        if candidate.exists() {
            return Ok(candidate.clone());
        }
    }

    // Return the first candidate path even if it doesn't exist yet; the
    // caller will produce a helpful error message.
    Ok(candidates[0].clone())
}
