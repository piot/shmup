mod simulation::{SimulationRequest}
mod input::{Input}

struct Game {
    input: Input
}

impl Game {
    fn new() -> Game {
        Game {
            input: {..}
        }
    }

    #[host_call]
    fn tick(mut self) -> SimulationRequest {
        player_input := .input.tick()
        {
            player_input: player_input
        }
    }
}