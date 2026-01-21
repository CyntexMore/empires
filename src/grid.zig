const std = @import("std");
const rl = @import("raylib");
const constants = @import("constants.zig");
const terrain = @import("terrain.zig");

pub const TileCoord = struct {
    x: i32,
    y: i32,

    pub fn fromWorldPos(world_pos: rl.Vector2) TileCoord {
        return .{
            .x = @divFloor(@as(i32, @intFromFloat(world_pos.x)), constants.TILE_SIZE),
            .y = @divFloor(@as(i32, @intFromFloat(world_pos.y)), constants.TILE_SIZE),
        };
    }

    pub fn isValid(self: TileCoord) bool {
        return self.x >= 0 and
            self.x < constants.GRID_WIDTH and
            self.y >= 0 and
            self.y < constants.GRID_HEIGHT;
    }

    pub fn equals(self: TileCoord, other: TileCoord) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub const VisibleBounds = struct {
    min_x: i32,
    min_y: i32,
    max_x: i32,
    max_y: i32,
};

pub const Grid = struct {
    selected_tile: ?TileCoord,
    map: [][]terrain.Tile,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, map: [][]terrain.Tile) Grid {
        return .{
            .selected_tile = null,
            .map = map,
            .allocator = allocator,
        };
    }

    pub fn selectTile(self: *Grid, tile: TileCoord) void {
        if (tile.isValid()) {
            self.selected_tile = tile;
        }
    }

    pub fn draw(self: Grid, hovered_tile: ?TileCoord, bounds: VisibleBounds) void {
        const min_y = @as(usize, @intCast(bounds.min_y));
        const max_y = @as(usize, @intCast(bounds.max_y));
        const min_x = @as(usize, @intCast(bounds.min_x));
        const max_x = @as(usize, @intCast(bounds.max_x));

        for (min_y..max_y) |y| {
            for (min_x..max_x) |x| {
                const tile_x = constants.TILE_SIZE * @as(i32, @intCast(x));
                const tile_y = constants.TILE_SIZE * @as(i32, @intCast(y));

                const tile_data = self.map[y][x];
                rl.drawRectangle(
                    tile_x,
                    tile_y,
                    constants.TILE_SIZE,
                    constants.TILE_SIZE,
                    tile_data.terrain.getColor(),
                );

                if (tile_data.resources) |res| {
                    const resource_color = switch (res) {
                        .gold => rl.Color.init(255, 215, 0, 255),
                        .iron => rl.Color.init(105, 105, 105, 255),
                        .wood => rl.Color.init(139, 69, 19, 255),
                        .stone => rl.Color.init(128, 128, 128, 255),
                        .coins => rl.Color.init(255, 223, 0, 255),
                    };
                    rl.drawCircle(
                        tile_x + @divTrunc(constants.TILE_SIZE, 2),
                        tile_y + @divTrunc(constants.TILE_SIZE, 2),
                        8,
                        resource_color,
                    );
                }
            }
        }

        if (self.selected_tile) |sel| {
            if (sel.x >= bounds.min_x and sel.x < bounds.max_x and
                sel.y >= bounds.min_y and sel.y < bounds.max_y)
            {
                rl.drawRectangle(
                    sel.x * constants.TILE_SIZE,
                    sel.y * constants.TILE_SIZE,
                    constants.TILE_SIZE,
                    constants.TILE_SIZE,
                    rl.Color.init(255, 255, 255, 80),
                );
            }
        }

        if (hovered_tile) |hovered| {
            if (hovered.x >= bounds.min_x and hovered.x < bounds.max_x and
                hovered.y >= bounds.min_y and hovered.y < bounds.max_y)
            {
                rl.drawRectangle(
                    hovered.x * constants.TILE_SIZE,
                    hovered.y * constants.TILE_SIZE,
                    constants.TILE_SIZE,
                    constants.TILE_SIZE,
                    rl.Color.init(255, 255, 255, 50),
                );
            }
        }
    }
};

