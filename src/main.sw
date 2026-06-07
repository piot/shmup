// Copyright (c) 2026 Peter Björklund.
// Licensed under the MIT License.

mod simulation::{Logic, SimulationRequest}
mod render::{Render}
mod audio::{Audio}
mod game::{Game}

// These are compile time allocations, that the engine will use in runtime

anchor simulation = Logic::new()
anchor simulation_request = SimulationRequest { .. }
anchor render = Render::new()
anchor audio = Audio::new()
anchor game = Game::new()
