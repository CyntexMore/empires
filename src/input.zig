const rl = @import("raylib");
const std = @import("std");

pub const InputState = struct {
    last_mouse_position: rl.Vector2,
    is_panning: bool,

    pub fn init() InputState {
        return .{
            .last_mouse_position = .{ .x = 0, .y = 0 },
            .is_panning = false,
        };
    }

    pub fn getPanDelta(self: *InputState, current_mouse_pos: rl.Vector2) ?rl.Vector2 {
        if (rl.isMouseButtonPressed(.left)) {
            self.last_mouse_position = current_mouse_pos;
            self.is_panning = false;
            return null;
        }

        if (rl.isMouseButtonDown(.left)) {
            const delta = rl.Vector2{
                .x = self.last_mouse_position.x - current_mouse_pos.x,
                .y = self.last_mouse_position.y - current_mouse_pos.y,
            };

            if (@abs(delta.x) > 2 or @abs(delta.y) > 2) {
                self.is_panning = true;
                self.last_mouse_position = current_mouse_pos;
                return delta;
            }

            self.last_mouse_position = current_mouse_pos;
        }

        return null;
    }

    pub fn shouldSelectTile(self: InputState) bool {
        return rl.isMouseButtonReleased(.left) and !self.is_panning;
    }
};

