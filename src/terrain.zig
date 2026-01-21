const std = @import("std");
const rl = @import("raylib");
const constants = @import("constants.zig");
const resources = @import("resources.zig");

pub const ResourceType = resources.ResourceType;

pub const TerrainType = enum(u8) {
    deep_water,
    shallow_water,
    sand,
    grass,
    forest,
    hills,
    mountains,

    pub fn getColor(self: TerrainType) rl.Color {
        return switch (self) {
            .deep_water => rl.Color.init(20, 60, 120, 255),
            .shallow_water => rl.Color.init(60, 120, 180, 255),
            .sand => rl.Color.init(210, 180, 140, 255),
            .grass => rl.Color.init(80, 150, 60, 255),
            .forest => rl.Color.init(40, 100, 40, 255),
            .hills => rl.Color.init(120, 100, 80, 255),
            .mountains => rl.Color.init(150, 150, 150, 255),
        };
    }

    pub fn isWalkable(self: TerrainType) bool {
        return switch (self) {
            .deep_water => false,
            .shallow_water => false,
            .mountains => false,
            else => true,
        };
    }

    pub fn getMovementCost(self: TerrainType) f32 {
        return switch (self) {
            .sand => 1.2,
            .grass => 1.0,
            .forest => 1.5,
            .hills => 2.0,
            else => 999.0,
        };
    }
};

pub const Tile = struct {
    terrain: TerrainType,
    resources: ?ResourceType = null,
};

