// Copyright (c) 2026 Peter Björklund.
// Licensed under the MIT License.

use lily::input::{get_active_devices, set_active_action_set, get}
mod simulation::{PlayerInput}

#[actionset]
struct SpaceCraft {
    move: (Float, Float)
    fire: Bool
    ability1: Bool
    cursor: (Int, Int)
}

// TODO: Handle overlays


struct Input {
    dummy: Int
}

impl Input {
    fn tick(mut self) -> PlayerInput {
        self.dummy = 1
        active_devices: Vec<Int; 8> = get_active_devices()
        mut fire := false
        mut move := (0.0, 0.0)

        for device_id in active_devices {
            set_active_action_set::<SpaceCraft>(device_id)
            input: SpaceCraft = get(device_id)

            fire |= input.fire
            x, y = input.move

            if x.abs() > 0.01 || y.abs() > 0.01 {
                move = (x, y)
            }

            //_found_type := get_device_type(device_id)
            //_action_source := get_action_source::<SpaceCraft>("fire", device_id)
        }
        PlayerInput {
            fire: fire
            move: move
        ..}
    }
}