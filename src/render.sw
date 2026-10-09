// Copyright (c) 2026 Peter Björklund.
// Licensed under the MIT License.

mod simulation
use gfx::sprite::{SpriteSheet, Sprites, SpriteAtlasUniform, SpriteInstance}
use gfx::scrolling::{ScrollingTexture, ScrollingInstance, ScrollingTextureUniform}
use gfx::nine_slice::{NineSliceCommon, NineSliceConfig, PixelSize, NineSliceInfo, NineSliceBindGroup, NineSliceInstances}
use lily::wgpu
use lily::gm
use lily::bmf
use lily::wgpu_types::{Vec4f, Vec2f, Mat4f}
use gfx::msdf::{FontCommon}
use gfx::font::{FontAtlasBindGroup, GlyphInstances}
use gfx::particles::{ParticleCommon, ParticleBindGroup, ParticleInstances}
const VIRTUAL_SCREEN_HEIGHT = 180
const VIRTUAL_SCREEN_WIDTH = 320
const PARTICLES_PER_EXPLOSION = 12
const EXPLOSION_PRESENTATION_LIFETIME = 0.46
const PRESENTATION_COUNT = 128
const LOOKUP_COUNT = 64
const TWO_PI = 6.28

const EXPLOSION_SEED_ID_FACTOR = 0.33
const EXPLOSION_SEED_PARTICLE_FACTOR = 1.77
const EXPLOSION_SEED_TICK_MASK = 0xFFFF
const EXPLOSION_CENTER_OFFSET = 4.0
const EXPLOSION_DISTANCE_TIME_SCALE = 60.0
const EXPLOSION_ANGLE_VARIATION_FREQUENCY = 3.17
const EXPLOSION_ANGLE_VARIATION = 0.7
const EXPLOSION_SPEED_VARIATION_FREQUENCY = 2.13
const EXPLOSION_SPEED_MIN = 0.06
const EXPLOSION_SPEED_RANGE = 0.18
const EXPLOSION_OFFSET_VARIATION_FREQUENCY = 1.37
const EXPLOSION_OFFSET_MAX = 0.8
const EXPLOSION_LIFE_VARIATION_FREQUENCY = 0.71
const EXPLOSION_LIFE_MIN = 0.18
const EXPLOSION_LIFE_RANGE = 0.14
const EXPLOSION_POWER_VARIATION_FREQUENCY = 1.93
const EXPLOSION_POWER_MIN = 0.78
const EXPLOSION_POWER_RANGE = 0.16

struct Position {
    x: Float
    y: Float
}

struct PresentedExplosion {
    simulation_created_at: Int
    simulation_id: Int

    active: Bool
    age: Float
    position: Position
}

struct ExplosionLookup {
    simulation_id: Int
    active: Bool
    presentation_index: Int
    last_seen: Int
}

struct Render {
    sprites: Sprites

    ship_atlas: SpriteSheet
    projectile_atlas: SpriteSheet
    ship_atlas_info: SpriteAtlasUniform
    enemies_atlas: SpriteSheet
    enemies_atlas_info: SpriteAtlasUniform
    projectile_atlas_info: SpriteAtlasUniform

    background_texture: wgpu::TextureHandle
    background_texture_view: wgpu::TextureViewHandle
    background_scroll: ScrollingTexture
    background_scroll_bind_groups: wgpu::BindGroupHandle

    font: FontCommon
    font_atlas: FontAtlasBindGroup
    glyphs: GlyphInstances
    bm_font: bmf::BmFont

    nine_slice: NineSliceCommon
    nine_slice_atlas: NineSliceBindGroup
    first_nine_slice: NineSliceConfig
    nine_slice_instances: NineSliceInstances

    particle: ParticleCommon
    particle_atlas: ParticleBindGroup
    particles: ParticleInstances
    explosions: [PresentedExplosion; PRESENTATION_COUNT]
    explosion_lookup: [ExplosionLookup; LOOKUP_COUNT]
    tick_id: Int
    particle_count: Int

    view_proj: Mat4f
}

const PI: Float = 3.14159

impl Render {
    fn new() -> Render {
        mut sprites := Sprites::new()

        sprite_view_proj := gm::Mat4::ortho_2d_pixel_near_far_int(
            VIRTUAL_SCREEN_WIDTH
            VIRTUAL_SCREEN_HEIGHT
            0
            128
        ).to_mat4f()

        background_texture := wgpu::create_sampled_texture_png(
            @blue_nebula_04_512x512.png
            Rgba8UnormSrgb
            "background texture"
        )
        background_texture_view := wgpu::create_texture_view(
            background_texture
            "background texture view"
        )

        background_scroll := ScrollingTexture::new()

        background_scroll_bind_groups := wgpu::create_bind_group(
            background_scroll.scroll_bind_group_layout
            [
                UniformBuffer(background_scroll.scroll_info_uniform_buffer)
                TextureView(background_texture_view)
                Sampler(background_scroll.repeat_sampler)
            ]
            "sprite bind group 0"
        )

        font_common := FontCommon::new(sprite_view_proj)

        fnt: bmf::BmFontResXml = @fonts/example.fnt

        nine_slice_texture_size := PixelSize {
            width: 256
            height: 64
        }

        nine_slice_info := NineSliceInfo {
            pos: [0, 0]
            size: [39, 37]
            borders: [16, 16, 16, 16]
        }
        nine_slice := NineSliceCommon::new(sprite_view_proj)
        nine_slice_atlas := nine_slice.create_atlas(@nine_slice/nine_slice.png)
        particle := ParticleCommon::new(sprite_view_proj)


        {
            font: font_common
            font_atlas: font_common.create_atlas(@fonts/example.png, "example")
            glyphs: GlyphInstances::new()
            bm_font: fnt.load()

            nine_slice: nine_slice
            nine_slice_atlas: nine_slice_atlas

            first_nine_slice: NineSliceConfig::new_from(
                nine_slice_info
                nine_slice_texture_size
            )
            nine_slice_instances: NineSliceInstances::new()

            particle: particle
            particle_atlas: particle.create_atlas(@smoke_01.png)
            particles: ParticleInstances::new()
            explosions: [
                {
                    active: false
                    simulation_id: -1
                    simulation_created_at: -1
                    age: 0.0
                    position: [0.0, 0.0]
                }
            ]
            explosion_lookup: [
                {
                    active: false
                    simulation_id: -1
                    presentation_index: -1
                    last_seen: -1
                }
            ]
            tick_id: 0
            particle_count: 0

            view_proj: sprite_view_proj
            // Background scroll
            background_texture: background_texture
            background_texture_view: background_texture_view
            background_scroll: background_scroll
            background_scroll_bind_groups: background_scroll_bind_groups

            sprites: sprites
            ship_atlas: sprites.sprite_sheet(@player/ship_16x16.png)
            projectile_atlas: sprites.sprite_sheet(@projectiles/projectiles.png)
            enemies_atlas: sprites.sprite_sheet(@enemies/enemies.png)
            ship_atlas_info: SpriteAtlasUniform {
                view_proj: sprite_view_proj
                sprite_size: [16.0, 16.0]
                atlas_cols: 3
                atlas_rows: 1
            }
            projectile_atlas_info: SpriteAtlasUniform {
                view_proj: sprite_view_proj
                sprite_size: Vec2f {
                    x: 16.0
                    y: 16.0
                }
                atlas_cols: 8
                atlas_rows: 1
            }
            enemies_atlas_info: SpriteAtlasUniform {
                view_proj: sprite_view_proj
                sprite_size: Vec2f {
                    x: 16.0
                    y: 16.0
                }
                atlas_cols: 6
                atlas_rows: 6
            }
        }
    }

    #[host_call]
    fn tick(mut self, sim: simulation::Logic) {
        for mut presentation in .explosions {
            if presentation.active {
                presentation.age += 0.016 // TODO: use Int age
            }
        }
        .tick_id += 1
        for explosion_id, explosion in sim.explosions {
            mut lookup_index := -1
            mut presentation_index := -1
            for i, lookup in .explosion_lookup {
                if lookup.active && lookup.simulation_id == explosion_id {
                    lookup_index = i
                    presentation_index = lookup.presentation_index
                    break
                }
            }

            if lookup_index < 0 {
                for i, lookup in .explosion_lookup {
                    if !lookup.active {
                        lookup_index = i
                        break
                    }
                }

                if lookup_index >= 0 {
                    for i, explosion in .explosions {
                        if !explosion.active {
                            presentation_index = i
                            break
                        }
                    }

                    if presentation_index >= 0 {
                        .explosion_lookup[lookup_index] = {
                            active: true
                            simulation_id: explosion_id
                            presentation_index: presentation_index
                            last_seen: .tick_id
                        }
                        .explosions[presentation_index] = {
                            active: true
                            simulation_id: explosion_id
                            simulation_created_at: explosion.created_at
                            age: 0.0
                            position: [explosion.pos.x, explosion.pos.y]
                        }
                    }
                }
            } else {
                .explosion_lookup[lookup_index].last_seen = .tick_id
                if presentation_index >= 0 {
                    with mut presentation = &.explosions[presentation_index] {
                        presentation.position = [
                            explosion.pos.x
                            explosion.pos.y
                        ]
                    }
                }
            }
        }

        for mut lookup in .explosion_lookup {
            if lookup.active && lookup.last_seen != .tick_id {
                lookup.active = false
            }
        }

        for mut explosion in .explosions {
            if explosion.active
                && explosion.age >= EXPLOSION_PRESENTATION_LIFETIME {
                explosion.active = false
            }
        }

        particle_count: Int : for presentation in .explosions {
            if !presentation.active {
                continue
            }

            age := presentation.age
            seed_tick := (presentation.simulation_created_at & EXPLOSION_SEED_TICK_MASK).float()
            seed_base := seed_tick + presentation.simulation_id.float() * EXPLOSION_SEED_ID_FACTOR
            center_x := presentation.position.x + EXPLOSION_CENTER_OFFSET
            center_y := presentation.position.y + EXPLOSION_CENTER_OFFSET

            for particle_id in 0..PARTICLES_PER_EXPLOSION {
                particle_index := particle_count + particle_id
                seed := seed_base + particle_id.float() * EXPLOSION_SEED_PARTICLE_FACTOR
                angle := seed * TWO_PI + (seed * EXPLOSION_ANGLE_VARIATION_FREQUENCY).sin() * EXPLOSION_ANGLE_VARIATION
                speed := EXPLOSION_SPEED_MIN + ((seed * EXPLOSION_SPEED_VARIATION_FREQUENCY).sin() + 1.0) * EXPLOSION_SPEED_RANGE
                initial_offset := ((seed * EXPLOSION_OFFSET_VARIATION_FREQUENCY).cos() + 1.0) * EXPLOSION_OFFSET_MAX
                life := EXPLOSION_LIFE_MIN + ((seed * EXPLOSION_LIFE_VARIATION_FREQUENCY).cos() + 1.0) * EXPLOSION_LIFE_RANGE
                power_scale := EXPLOSION_POWER_MIN + ((seed * EXPLOSION_POWER_VARIATION_FREQUENCY).sin() + 1.0) * EXPLOSION_POWER_RANGE
                remaining_life := life - age
                direction_x := angle.cos()
                direction_y := angle.sin()
                distance := initial_offset + speed * age * EXPLOSION_DISTANCE_TIME_SCALE

                with mut particle = &.particles.instances[particle_index] {
                    particle.position = [
                        center_x + direction_x * distance
                        center_y + direction_y * distance
                    ]
                    particle.power = if remaining_life > 0.0 {
                        particle_age := 1.0 - remaining_life.div(life)
                        unscaled_power := if particle_age < 0.35 {
                            0.55 + particle_age * 1.2
                        } else {
                            (1.0 - particle_age) * 1.8
                        }

                        unscaled_power * power_scale
                    } else {
                        0.0
                    }
                }
            }
            particle_count += PARTICLES_PER_EXPLOSION
        }
        .particle_count = particle_count
        if .particle_count > 0 .particles.write(.particle_count)
    }

    #[host_call]
    fn render(mut self, sim: simulation::Logic) {

        normalized_int_time := sim.tick_count % 62800
        normalized_float_time := normalized_int_time.float() * 0.05

        time := sim.tick_count.float() / 30.0

        //mut glyph_count := 0
        mut pen_x := 100
        pen_y := 100

        atlas_w := 248.0
        atlas_h := 237.0

        text_scale := 0.2

        codepoints: Vec<Char; 32> = "Shmup".chars() // we call chars() since we want the Codepoint (Unicode) instead of a U8
        glyph_count: Int : for idx, codepoint in codepoints {
            g := .bm_font.glyphs[codepoint]
            u := g.x.float().div(atlas_w)
            v := g.y.float().div(atlas_h)
            uw := g.width.float().div(atlas_w)
            vh := g.height.float().div(atlas_h)
            dst_x := pen_x + g.x_offset
            dst_y := pen_y - g.y_offset // Font assumes y going down, so we invert it
            //modified_y := (normalized_float_time + idx.float()).sin() * 1.0
            modified_intensity := 0.3 + ((normalized_float_time * 0.4 + idx.float() * 0.5).cos() + 1.0) * 0.7
            alpha :=
                | idx != 0 -> 1.0
                | _ -> 0.4
            .glyphs.glyphs[glyph_count] = {
                dst_rect: Vec4f {
                    x: dst_x.float() * text_scale
                    y: dst_y.float() * text_scale
                    z: g.width.float() * text_scale
                    w: -g.height.float() * text_scale // Font assumes y going down, so we invert it
                }
                uv_rect: Vec4f {
                    x: u
                    y: v
                    z: uw
                    w: vh
                }
                color: Vec4f {
                    x: modified_intensity
                    y: 0.1
                    z: modified_intensity * 0.3
                    w: alpha
                }
            }
            glyph_count += 1
            pen_x = pen_x + g.x_advance
        }
        mut sprite_instances: Block<SpriteInstance; 32>

        // === Add Render Passes ===
        // Sprite Pass =============
        mut sprite_pass: wgpu::RenderPass
        sprite_pass.depth_attachment = -1


        // === Background ===
        sprite_pass.set_pipeline(.background_scroll.scroll_pipeline)
        sprite_pass.set_bind_group(0, .background_scroll_bind_groups)
        sprite_pass.set_vertex_buffer(
            0
            .background_scroll.sprite_quad_vertices
        )
        sprite_pass.set_vertex_buffer(
            1
            .background_scroll.scroll_instance_buffers
        )
        sprite_pass.set_index_buffer(.background_scroll.sprite_quad_indices)

        sprite_pass.draw_indexed([0, 6], [0, 1])

        scroll_info_uniform := ScrollingTextureUniform {
            view_proj: .view_proj
            uv_offset: [time * 0.02, 0.5]
            uv_scale: [1.0, 1.5]
            tint: [0.6, 0.6, 0.6, 1.0]
        }
        mut scrolling_instances: Block<ScrollingInstance; 64>
        scrolling_instances[0] = ScrollingInstance {
            local_pos: [-0.5, -0.5]
            world_pos: [320.0, 480.0]
            size: [1.0, 1.0]
        }
        .background_scroll.scroll_instance_buffers.write_at(
            block: scrolling_instances
            count: 1
        ..)
        .background_scroll.scroll_info_uniform_buffer.write(scroll_info_uniform)

        // Nine Slice
        sprite_pass.set_pipeline(.nine_slice.pipeline.handle)
        sprite_pass.set_bind_group(0, .nine_slice.uniform_bind_group)

        sprite_pass.set_vertex_buffer(0, .nine_slice.corners.vertex_buffer)
        sprite_pass.set_vertex_buffer(
            1
            .nine_slice_instances.vertex_instance_buffer
        )
        sprite_pass.set_index_buffer(.nine_slice.corners.index_buffer)

        // Switch atlas
        sprite_pass.set_bind_group(1, .nine_slice_atlas.handle)


        .nine_slice_instances.instances[0] = .first_nine_slice.fill_instance(
            [270, 10]
            {
                width: 40
                height: 40
            }
        )
        sprite_pass.draw_indexed([0, 54], [0, 1])

        .nine_slice_instances.vertex_instance_buffer.write_with(
            slice: .nine_slice_instances.instances[0..1]
        ..)

        // Sprite PIPELINE
        .sprites.set_pipeline(&sprite_pass) // pipeline must be first
        .sprites.set_instances(&sprite_pass) // set the index vertex buffer (sprite instances)

        mut sprite_index := 0
        mut sprite_index_start := 0


        // Ships
        for ship in sim.ships {
            ship_pos := (
                ship.rect.pos.x.floor() - 8,
                ship.rect.pos.y.floor() - 8
            ) // 8 pixels to center
            ship_frame := match ship.direction.y.sign() {
                1.0 -> 0
                -1.0 -> 2
                _ -> 1
            }

            x, y = ship_pos
            screen_x := x.float()
            screen_y := y.float()

            sprite_instances[sprite_index] = SpriteInstance {
                position: {
                    x: screen_x
                    y: screen_y
                }
                scale: [1.0, 1.0]
                sprite_index: ship_frame
                tint_color: 0xFFffffFF
                rotation: 1.5 * PI
                pivot: [8.0, 8.0]
                flags: 0
            }
            sprite_index += 1

            // Ship booster
            booster_value: Int? =
                | ship.direction.x > 0.6 -> 0
                | ship.direction.x > 0.0 -> 1
                | _ -> none

            if booster_value {
                //x, y = ship_pos
                //adjusted_pos := (x - 15, y, 0)
                //normalized_x_movement := ship.direction.x.abs() / 0.6
                // color: Color::new(1.0, 1.0, 1.0, normalized_x_movement),
            }
        }
        ship_count := sprite_index - sprite_index_start
        if ship_count > 0 {
            .ship_atlas.write_atlas_info(.ship_atlas_info) // atlas information
            .sprites.set_atlas(&sprite_pass, .ship_atlas) // sets bind group
            //info('ship_atlas: {.ship_atlas} {sprite_index_start}, {count}')
            sprite_pass.draw_indexed([0, 6], [sprite_index_start, ship_count]) // draw sprite instances that "belongs" to this atlas
            sprite_index_start = sprite_index
        }


        // Projectiles
        for shot in sim.shots {
            shot_pos := (shot.x.floor() - 8, shot.y.floor() - 8) // 8 pixels to center
            x, y = shot_pos
            sprite_instances[sprite_index] = SpriteInstance {
                position: {
                    x: x.float()
                    y: y.float()
                } // world position (x, y)
                scale: [1.0, 1.0] // scale multiplier
                sprite_index: 4 // index into sprite atlas
                tint_color: 0xFFFFFFFF // packed RGBA8 (white, full alpha)
                rotation: 3.0 * (PI / 2.0) // rotation in radians
                pivot: [8.0, 8.0] // pivot point in pixels
                flags: 0 // flip flags
            }
            sprite_index += 1
        }

        projectile_count := sprite_index - sprite_index_start
        if projectile_count > 0 {
            .projectile_atlas.write_atlas_info(.projectile_atlas_info) // atlas information. could be done at the end
            .sprites.set_atlas(&sprite_pass, .projectile_atlas) // sets bind group
            //info('projectile: {.projectile_atlas}  {sprite_index_start}, {count}')
            sprite_pass.draw_indexed(
                [0, 6]
                [sprite_index_start, projectile_count]
            ) // draw sprite instances that "belongs" to this atlas
            sprite_index_start = sprite_index
        }


        for enemy in sim.enemies {
            frame_offset := match enemy.enemy {
                Alan -> 0
                BonBon -> 6
                Lips -> 12
            }
            enemy_pos := (enemy.rect.pos.x.floor(), enemy.rect.pos.y.floor())
            x, y = enemy_pos
            screen_x := x.float()
            screen_y := y.float()

            pulsating_time := enemy.could_be_together.time % 53
            frame := if pulsating_time < 40 pulsating_time / 10 else 0

            sprite_instances[sprite_index] = {
                position: {
                    x: screen_x + 10.0
                    y: screen_y
                }
                scale: [1.0, 1.0]
                sprite_index: frame_offset + frame // index into the sprite atlas
                tint_color: 0xFFFFFFFF // packed RGBA8 (white, full alpha)
                rotation: 0.0 // rotation in radians
                pivot: [8.0, 8.0] // pivot point in pixels
                flags: 0
            }

            sprite_index += 1
        }

        enemy_count := sprite_index - sprite_index_start
        if enemy_count > 0 {
            .enemies_atlas.write_atlas_info(.enemies_atlas_info) // could be done in the end

            .sprites.set_atlas(&sprite_pass, .enemies_atlas) // sets bind group
            //info('projectile: {.enemies_atlas}  {sprite_index_start}, {count}')
            sprite_pass.draw_indexed([0, 6], [sprite_index_start, enemy_count]) // draw sprite instances that "belongs" to this atlas
            sprite_index_start = sprite_index
        }

        if sprite_index > 0 {
            // Copy sprite instances from Swamp memory to WGPU memory
            .sprites.sprite_instance_buffers.write_at(
                block: sprite_instances
                count: sprite_index
            ..)
        }

        // Particles
        sprite_pass.set_pipeline(.particle.pipeline.handle)
        sprite_pass.set_vertex_buffer(0, .particle.quads.vertex_buffer)
        sprite_pass.set_vertex_buffer(1, .particles.vertex_instance_buffer)
        sprite_pass.set_bind_group(0, .particle.uniform_bind_group)
        sprite_pass.set_bind_group(1, .particle_atlas.handle)
        sprite_pass.set_index_buffer(.particle.quads.index_buffer)
        sprite_pass.draw_indexed([0, 6], [0, .particle_count])

        // === Text / Fonts ===
        sprite_pass.set_pipeline(.font.pipeline.handle)
        sprite_pass.set_vertex_buffer(
            slot: 0
            vertex_buffer: .font.base.quads.vertex_buffer
        )
        sprite_pass.set_vertex_buffer(
            slot: 1
            vertex_buffer: .glyphs.vertex_instance_buffer
        )

        // For each font atlas
        sprite_pass.set_bind_group(0, .font_atlas.bind_group)

        // instanced rendering. reuse two triangles (quad) to render all glyphs
        sprite_pass.set_index_buffer(.font.base.quads.index_buffer)
        sprite_pass.draw_indexed([0, 6], [0, glyph_count])

        // Update instance buffer somewhere during render
        .glyphs.vertex_instance_buffer.write_at(
            0
            .glyphs.glyphs
            0
            glyph_count
        )

        // Pass is done
        wgpu::add_pass(sprite_pass, "sprite pass")
    }

    #[host_call]
    fn resize(mut _self) {}
}