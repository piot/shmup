mod simulation
use gfx::sprite::{SpriteSheet, Sprites, SpriteAtlasUniform, SpriteInstance}
use gfx::scrolling::{ScrollingTexture, ScrollingInstance, ScrollingTextureUniform}
use lily::wgpu
use lily::gm
use lily::wgpu_types::{Vec2f, Mat4f}

const VIRTUAL_SCREEN_HEIGHT = 180
const VIRTUAL_SCREEN_HEIGHT_F = 180.float()
const VIRTUAL_SCREEN_WIDTH = 320

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

    view_proj: Mat4f

    timer: Int
}

const PI: Float = 3.14159

impl Render {
    fn new() -> Render {
        mut sprites := Sprites::new()


        sprite_view_proj := gm::Mat4::ortho_2d_pixel_near_far_int(VIRTUAL_SCREEN_WIDTH, VIRTUAL_SCREEN_HEIGHT, 0, 128).to_mat4f()

        background_texture := wgpu::create_sampled_texture_png(@blue_nebula_04_512x512.png, Rgba8UnormSrgb, 'background texture')
        background_texture_view := wgpu::create_texture_view(background_texture, 'background texture view')

        background_scroll := ScrollingTexture::new()

        background_scroll_bind_groups := wgpu::create_bind_group(background_scroll.scroll_bind_group_layout, [
            Buffer(background_scroll.scroll_info_uniform_buffer),
            TextureView(background_texture_view),
            Sampler(background_scroll.repeat_sampler)
        ], 'sprite bind group 0')

        {
            view_proj: sprite_view_proj
            // Background scroll
            background_texture: background_texture
            background_texture_view:  background_texture_view
            background_scroll: background_scroll
            background_scroll_bind_groups: background_scroll_bind_groups

            sprites: sprites
            ship_atlas: sprites.sprite_sheet(@player/ship_16x16.png)
            projectile_atlas: sprites.sprite_sheet(@projectiles/projectiles.png)
            enemies_atlas: sprites.sprite_sheet(@enemies/enemies.png)
            ship_atlas_info: SpriteAtlasUniform {
                view_proj: sprite_view_proj
                sprite_size: [ 16.0, 16.0]
                atlas_cols: 3
                atlas_rows: 1
            }
            projectile_atlas_info: SpriteAtlasUniform {
                view_proj: sprite_view_proj
                sprite_size: Vec2f { x: 16.0, y: 16.0 }
                atlas_cols: 8
                atlas_rows: 1
            }
            enemies_atlas_info: SpriteAtlasUniform {
                view_proj: sprite_view_proj
                sprite_size: Vec2f { x: 16.0, y: 16.0 }
                atlas_cols: 6
                atlas_rows: 6
            }
            timer: 0
        }
    }

    #[host_call]
    fn render(mut self, sim: simulation::Logic) {
        .timer += 1

        time := (.timer.float() / 30.0)

        //sway := (((time * 2.0).cos() * 2.0) + 1.0) / 2.0
        //angle := time * 2.0

        mut sprite_instances: Block<SpriteInstance; 32>

        //mut bind_group_draws: Vec<BindGroupInfo; 10>

        // === Fill in instances and copy to wgpu ==

        // === Add Render Passes ===
        // Sprite Pass =============
        mut sprite_pass: wgpu::RenderPass
        sprite_pass.depth_attachment = -1


        // === Background ===
        //sprite_view_proj := gm::Mat4::ortho_2d_int(320, 200, 1.0).to_mat4f()

        sprite_pass.set_pipeline(.background_scroll.scroll_pipeline)
        sprite_pass.set_bind_group(0, .background_scroll_bind_groups)
        sprite_pass.set_vertex_buffer(0, .background_scroll.sprite_quad_vertices)
        sprite_pass.set_vertex_buffer(1, .background_scroll.scroll_instance_buffers)
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
            local_pos: [0.0, 0.0]
            world_pos: [320.0, 480.0]
            size: [1.0, 1.0]
        }
        .background_scroll.scroll_instance_buffers.write(scrolling_instances)
        .background_scroll.scroll_info_uniform_buffer.write(scroll_info_uniform)


        // Sprite PIPELINE
        .sprites.set_pipeline(&sprite_pass) // pipeline must be first
        .sprites.set_instances(&sprite_pass) // set the index vertex buffer (sprite instances)


        mut sprite_index = 0
        mut sprite_index_start = 0

        // Ships
        for ship in sim.ships {
            ship_pos := (ship.rect.pos.x.floor() - 8, ship.rect.pos.y.floor() - 8) // 8 pixels to center
            ship_frame := match ship.direction.y.sign() {
                1.0 -> 0, // need , here to avoid 0-1.0 confusion
                -1.0 -> 2,
                _ -> 1,
            }

            x, y = ship_pos
            screen_x := x.float()
            screen_y := y.float()

            sprite_instances[sprite_index] = SpriteInstance {
                position: { x: screen_x, y: screen_y }
                scale: [1.0, 1.0]
                sprite_index: ship_frame
                tint_color: 0xFFFFFFFF
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

        mut count := sprite_index - sprite_index_start
        if count > 0 {
            .ship_atlas.write_atlas_info(.ship_atlas_info) // atlas information
            .sprites.set_atlas(&sprite_pass, .ship_atlas) // sets bind group
            //info('ship_atlas: {.ship_atlas} {sprite_index_start}, {count}')
            sprite_pass.draw_indexed( [0, 6], [sprite_index_start, count] ) // draw sprite instances that "belongs" to this atlas
            sprite_index_start = sprite_index
        }

        // Projectiles
        for shot in sim.shots {
            shot_pos := (shot.x.floor() - 8, shot.y.floor() - 8) // 8 pixels to center
            x, y = shot_pos
            sprite_instances[sprite_index] = SpriteInstance {
                position: { x: x.float(), y: y.float() } ,   // world position (x, y)
                scale: [1.0, 1.0]       // scale multiplier
                sprite_index: 4         // index into sprite atlas
                tint_color: 0xFFFFFFFF  // packed RGBA8 (white, full alpha)
                rotation: 3.0 * (PI / 2.0)           // rotation in radians
                pivot: [8.0, 8.0]       // pivot point in pixels
                flags: 0                // flip flags
            }
            sprite_index += 1
        }

        count = sprite_index - sprite_index_start
        if count > 0 {
            .projectile_atlas.write_atlas_info(.projectile_atlas_info) // atlas information. could be done at the end
            .sprites.set_atlas(&sprite_pass, .projectile_atlas) // sets bind group
            //info('projectile: {.projectile_atlas}  {sprite_index_start}, {count}')
            sprite_pass.draw_indexed( [0, 6], [sprite_index_start, count] ) // draw sprite instances that "belongs" to this atlas
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
            frame := if pulsating_time < 40  pulsating_time/10  else  0

            sprite_instances[sprite_index] = {
                position: { x: screen_x + 10.0, y: screen_y }
                scale: [1.0, 1.0]
                sprite_index: frame_offset + frame // index into the sprite atlas
                tint_color: 0xFFFFFFFF  // packed RGBA8 (white, full alpha)
                rotation: 0.0           // rotation in radians
                pivot: [8.0, 8.0]       // pivot point in pixels
                flags: 0
            }

            sprite_index += 1
        }

        count = sprite_index - sprite_index_start
        if count > 0 {
            .enemies_atlas.write_atlas_info(.enemies_atlas_info) // could be done in the end

            .sprites.set_atlas(&sprite_pass, .enemies_atlas) // sets bind group
            //info('projectile: {.enemies_atlas}  {sprite_index_start}, {count}')
            sprite_pass.draw_indexed( [0, 6], [sprite_index_start, count] ) // draw sprite instances that "belongs" to this atlas
            sprite_index_start = sprite_index
        }

        if sprite_index > 0 {
            // Copy sprite instances from Swamp memory to WGPU memory
            .sprites.sprite_instance_buffers.write(sprite_instances)
        }

        // Pass is done
        wgpu::add_pass(sprite_pass, 'sprite pass')
    }

    #[host_call]
    fn resize(mut _self) {
    }
}
