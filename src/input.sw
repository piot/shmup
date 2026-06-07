use lily::input::{get_active_devices, set_active_action_set, get}

struct PlayerInput {
	mouse_cursor_position: (Int, Int)
	mouse_left_button: Bool
	mouse_right_button: Bool
    mouse_wheel_line_delta: (Float, Float)
    move: (Float, Float)
    fire: Bool
}

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
    fn new() -> Input {
        Input {
            ..
        }
    }

    #[host_call]
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
            ..
        }
    }
}