const std = @import("std");
const rl = @import("raylib");
const utils = @import("utils.zig");

pub const IconTextures = struct {
    gold: rl.Texture2D,
    iron: rl.Texture2D,
    wood: rl.Texture2D,
    stone: rl.Texture2D,

    pub fn init() !IconTextures {
        return .{
            .gold = try rl.loadTexture(
                utils.getResourcePath("textures/icons/gold_icon.png"),
            ),
            .iron = try rl.loadTexture(
                utils.getResourcePath("textures/icons/iron_icon.png"),
            ),
            .wood = try rl.loadTexture(
                utils.getResourcePath("textures/icons/wood_icon.png"),
            ),
            .stone = try rl.loadTexture(
                utils.getResourcePath("textures/icons/stone_icon.png"),
            ),
        };
    }

    pub fn deinit(self: *IconTextures) void {
        rl.unloadTexture(self.gold);
        rl.unloadTexture(self.iron);
        rl.unloadTexture(self.wood);
        rl.unloadTexture(self.stone);
    }

    pub fn getForResource(self: IconTextures, resource: @import("resources.zig").ResourceType) ?rl.Texture2D {
        return switch (resource) {
            .gold => self.gold,
            .iron => self.iron,
            .wood => self.wood,
            .stone => self.stone,
            .coins => null,
        };
    }
};

