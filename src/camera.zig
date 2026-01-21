const rl = @import("raylib");
const std = @import("std");
const constants = @import("constants.zig");

pub const Camera = struct {
    camera: rl.Camera2D,

    pub fn init() Camera {
        return .{
            .camera = rl.Camera2D{
                .target = rl.Vector2{ .x = 0.0, .y = 0.0 },
                .offset = rl.Vector2{
                    .x = @as(f32, @floatFromInt(constants.SCREEN_WIDTH)) / 2,
                    .y = @as(f32, @floatFromInt(constants.SCREEN_HEIGHT)) / 2,
                },
                .rotation = 0.0,
                .zoom = 1.0,
            },
        };
    }

    pub fn pan(self: *Camera, delta: rl.Vector2) void {
        self.camera.target.x += delta.x / self.camera.zoom;
        self.camera.target.y += delta.y / self.camera.zoom;
    }

    pub fn zoom(self: *Camera, mouse_position: rl.Vector2, wheel: f32) void {
        if (wheel == 0) return;

        const mouseWorldPos = rl.getScreenToWorld2D(mouse_position, self.camera);

        self.camera.zoom += wheel * constants.ZOOM_MULTIPLIER;
        self.camera.zoom = std.math.clamp(
            self.camera.zoom, 
            constants.MIN_ZOOM, 
            constants.MAX_ZOOM
        );

        const mouseWorldPosAfter = rl.getScreenToWorld2D(mouse_position, self.camera);

        self.camera.target.x += mouseWorldPos.x - mouseWorldPosAfter.x;
        self.camera.target.y += mouseWorldPos.y - mouseWorldPosAfter.y;
    }

    pub fn getWorldPosition(self: Camera, screen_pos: rl.Vector2) rl.Vector2 {
        return rl.getScreenToWorld2D(screen_pos, self.camera);
    }

    pub fn beginMode(self: Camera) void {
        rl.beginMode2D(self.camera);
    }

    pub fn endMode(_: Camera) void {
        rl.endMode2D();
    }

    pub fn getVisibleBounds(self: Camera) struct { min_x: i32, min_y: i32, max_x: i32, max_y: i32 } {
        const screen_w = @as(f32, @floatFromInt(constants.SCREEN_WIDTH));
        const screen_h = @as(f32, @floatFromInt(constants.SCREEN_HEIGHT));

        const top_left = rl.getScreenToWorld2D(.{ .x = 0, .y = 0 }, self.camera);
        const bottom_right = rl.getScreenToWorld2D(.{ .x = screen_w, .y = screen_h }, self.camera);

        const tile_size_f = @as(f32, @floatFromInt(constants.TILE_SIZE));
        const min_x = @as(i32, @intFromFloat(@floor(top_left.x / tile_size_f))) - 1;
        const min_y = @as(i32, @intFromFloat(@floor(top_left.y / tile_size_f))) - 1;
        const max_x = @as(i32, @intFromFloat(@ceil(bottom_right.x / tile_size_f))) + 1;
        const max_y = @as(i32, @intFromFloat(@ceil(bottom_right.y / tile_size_f))) + 1;

        return .{
            .min_x = @max(0, min_x),
            .min_y = @max(0, min_y),
            .max_x = @min(@as(i32, @intCast(constants.GRID_WIDTH)), max_x),
            .max_y = @min(@as(i32, @intCast(constants.GRID_HEIGHT)), max_y),
        };
    }
};

