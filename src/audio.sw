use lily::audio
mod simulation

struct Audio {
    last_processed_sim_tick: Int
    last_alien_explosion: Int
    last_shot_index: Int
}

const PLAYER_SHOT_VARIATIONS: [audio::SoundId; 3] = [
        @audio/shot1.wav
        @audio/shot2.wav
        @audio/shot3.wav
    ]

impl Audio {
    fn new() -> Audio {
        sound_definition := audio::SoundDefinition {
            adsr: {
                attack: 0
                decay: 100
                sustain: 0.8
                release: 100
            }
            root_note: 0
            gate_duration: 100
        }
        for variation in PLAYER_SHOT_VARIATIONS {
            audio::load_wav_stereo(variation, sound_definition)
        }

        audio::load_wav_stereo(@audio/alien_fire1.wav, sound_definition)



        {..}
    }

    #[host_call]
    fn tick(mut self, logic: simulation::Logic) {
        if audio::get_voice_state(0) == Idle {
            print('start a new song!')
            music_sound_definition := audio::SoundDefinition {
                adsr: {
                    attack: 100
                    decay: 100
                    sustain: 1.0
                    release: 100
                }
                root_note: 0
                gate_duration: 0
            }

            audio::stream_ogg_vorbis(0, music_sound_definition.root_note, @audio/short_song.ogg, music_sound_definition, 1.0)
        }
        for shot in logic.shots {
            if shot.created_at > .last_processed_sim_tick {
                match shot.faction {
                    Player -> {
                            voice_to_use := if audio::get_voice_state(1) != Idle {
                                1
                            } else {
                                2
                            }

                            audio::trig(voice_to_use, PLAYER_SHOT_VARIATIONS[.last_shot_index], 0.3)
                       }
                    Enemy -> {
                        voice_to_use := 3
                        if audio::get_voice_state(voice_to_use) != Idle {
                            continue
                        } 

                        audio::trig(voice_to_use, @audio/alien_fire1.wav, 0.3)
                    }
                }



                .last_shot_index += 1
                .last_shot_index %= 3
            }
        }

        for explosion in logic.explosions {
            if explosion.created_at > .last_processed_sim_tick {
                if logic.tick_count - .last_alien_explosion > 10 {
                    .last_alien_explosion = logic.tick_count
                }
            }
        }

        for ship in logic.ships {
            if ship.picked_up_bonus_at > .last_processed_sim_tick {
            }
        }

        .last_processed_sim_tick = logic.tick_count
    }
}