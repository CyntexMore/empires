const std = @import("std");
const rl = @import("raylib");
const constants = @import("constants.zig");
const Game = @import("game.zig").Game;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.initWindow(
        constants.SCREEN_WIDTH,
        constants.SCREEN_HEIGHT,
        "Empires",
    );
    defer rl.closeWindow();

    rl.setTargetFPS(constants.FRAME_TARGET);

    var game = try Game.init(allocator);
    defer game.deinit();

    while (!rl.windowShouldClose()) {
        game.update();

        rl.beginDrawing();
        defer rl.endDrawing();

        game.draw();
    }
}

