//! Factory definition API.
const std = @import("std");
const rl = @import("raylib");
const resources = @import("resources.zig");
const constants = @import("constants.zig");

pub const ResourceType = resources.ResourceType;
pub const ResourceBundle = resources.ResourceBundle;

/// Define new factory types easily by creating FactoryDef constants
pub const FactoryDef = struct {
    name: [:0]const u8,
    description: [:0]const u8 = "",

    /// Width of the factory in tiles
    width: u8,
    /// Height of the factory in tiles
    height: u8,

    /// Cost to build this factory
    build_cost: ResourceBundle,

    /// What this factory consumes per second (can be empty)
    inputs: []const ResourceRate,

    /// What this factory produces per second
    outputs: []const ResourceRate,

    /// Visual
    color: rl.Color = rl.Color.init(100, 100, 100, 255),

    pub fn getInputRate(self: FactoryDef, resource: ResourceType) f32 {
        for (self.inputs) |input| {
            if (input.resource == resource) return input.per_second;
        }
        return 0;
    }

    pub fn getOutputRate(self: FactoryDef, resource: ResourceType) f32 {
        for (self.outputs) |output| {
            if (output.resource == resource) return output.per_second;
        }
        return 0;
    }
};

pub const ResourceRate = struct {
    resource: ResourceType,
    per_second: f32,
};

pub const FACTORY_TYPES = struct {
    pub const MINT = FactoryDef{
        .name = "Mint",
        .description = "Converts gold into coins",
        .width = 2,
        .height = 2,
        .build_cost = .{ .wood = 100, .stone = 150 },
        .inputs = &.{.{ .resource = .gold, .per_second = 1.0 }},
        .outputs = &.{.{ .resource = .coins, .per_second = 10.0 }},
        .color = rl.Color.init(255, 215, 0, 255),
    };

    pub const SAWMILL = FactoryDef{
        .name = "Sawmill",
        .description = "Produces wood from nearby forests",
        .width = 2,
        .height = 1,
        .build_cost = .{ .wood = 30, .stone = 20 },
        .inputs = &.{},
        .outputs = &.{.{ .resource = .wood, .per_second = 2.0 }},
        .color = rl.Color.init(139, 90, 43, 255),
    };

    pub const QUARRY = FactoryDef{
        .name = "Quarry",
        .description = "Extracts stone from the earth",
        .width = 3,
        .height = 2,
        .build_cost = .{ .wood = 80, .coins = 50 },
        .inputs = &.{},
        .outputs = &.{.{ .resource = .stone, .per_second = 1.5 }},
        .color = rl.Color.init(128, 128, 128, 255),
    };

    pub const IRON_FOUNDRY = FactoryDef{
        .name = "Iron Foundry",
        .description = "Smelts iron ore into usable iron",
        .width = 2,
        .height = 2,
        .build_cost = .{ .wood = 60, .stone = 100, .coins = 100 },
        .inputs = &.{},
        .outputs = &.{.{ .resource = .iron, .per_second = 1.0 }},
        .color = rl.Color.init(70, 70, 80, 255),
    };

    pub const GOLD_MINE = FactoryDef{
        .name = "Gold Mine",
        .description = "Mines gold from deposits",
        .width = 2,
        .height = 2,
        .build_cost = .{ .wood = 100, .stone = 80, .iron = 50 },
        .inputs = &.{},
        .outputs = &.{.{ .resource = .gold, .per_second = 0.5 }},
        .color = rl.Color.init(218, 165, 32, 255),
    };

    pub const WEAPONS_FACTORY = FactoryDef{
        .name = "Weapons Factory",
        .description = "Forges weapons from iron for profit",
        .width = 3,
        .height = 2,
        .build_cost = .{ .wood = 150, .stone = 200, .iron = 100, .coins = 200 },
        .inputs = &.{.{ .resource = .iron, .per_second = 2.0 }},
        .outputs = &.{.{ .resource = .coins, .per_second = 25.0 }},
        .color = rl.Color.init(60, 60, 70, 255),
    };

    pub const ALL = [_]*const FactoryDef{
        &MINT,
        &SAWMILL,
        &QUARRY,
        &IRON_FOUNDRY,
        &GOLD_MINE,
        &WEAPONS_FACTORY,
    };
};

pub const FactoryInstance = struct {
    def: *const FactoryDef,
    x: i32,
    y: i32,
    owner_id: u8,
    active: bool = true,

    production_buffer: ResourceBundle = .{},

    pub fn update(self: *FactoryInstance, dt: f32, empire_resources: *ResourceBundle) void {
        if (!self.active) return;

        var can_produce = true;
        for (self.def.inputs) |input| {
            const needed = input.per_second * dt;
            if (empire_resources.get(input.resource) < needed) {
                can_produce = false;
                break;
            }
        }

        if (can_produce) {
            for (self.def.inputs) |input| {
                const amount = input.per_second * dt;
                _ = empire_resources.subtract(input.resource, amount);
            }

            for (self.def.outputs) |output| {
                const amount = output.per_second * dt;
                empire_resources.add(output.resource, amount);
            }
        }
    }

    pub fn draw(self: FactoryInstance) void {
        const tile_size = constants.TILE_SIZE;
        const px = self.x * tile_size;
        const py = self.y * tile_size;
        const w = @as(i32, self.def.width) * tile_size;
        const h = @as(i32, self.def.height) * tile_size;

        rl.drawRectangle(px, py, w, h, self.def.color);

        const border_color = if (self.active)
            rl.Color.init(255, 255, 255, 200)
        else
            rl.Color.init(100, 100, 100, 200);
        rl.drawRectangleLines(px, py, w, h, border_color);

        rl.drawRectangleLines(px + 2, py + 2, w - 4, h - 4, rl.Color.init(0, 0, 0, 100));
    }

    pub fn containsTile(self: FactoryInstance, tx: i32, ty: i32) bool {
        return tx >= self.x and tx < self.x + @as(i32, self.def.width) and
            ty >= self.y and ty < self.y + @as(i32, self.def.height);
    }
};

// Factory manager
pub const FactoryManager = struct {
    factories: std.ArrayList(FactoryInstance),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) FactoryManager {
        return .{
            .factories = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FactoryManager) void {
        self.factories.deinit(self.allocator);
    }

    pub fn addFactory(self: *FactoryManager, def: *const FactoryDef, x: i32, y: i32, owner_id: u8) !*FactoryInstance {
        try self.factories.append(self.allocator, .{
            .def = def,
            .x = x,
            .y = y,
            .owner_id = owner_id,
        });
        return &self.factories.items[self.factories.items.len - 1];
    }

    pub fn canPlaceFactory(self: FactoryManager, def: *const FactoryDef, x: i32, y: i32) bool {
        if (x < 0 or y < 0) return false;
        if (x + @as(i32, def.width) > @as(i32, constants.GRID_WIDTH)) return false;
        if (y + @as(i32, def.height) > @as(i32, constants.GRID_HEIGHT)) return false;

        for (self.factories.items) |factory| {
            const overlaps_x = x < factory.x + @as(i32, factory.def.width) and
                x + @as(i32, def.width) > factory.x;
            const overlaps_y = y < factory.y + @as(i32, factory.def.height) and
                y + @as(i32, def.height) > factory.y;
            if (overlaps_x and overlaps_y) return false;
        }

        return true;
    }

    pub fn getFactoryAt(self: FactoryManager, tx: i32, ty: i32) ?*FactoryInstance {
        for (self.factories.items) |*factory| {
            if (factory.containsTile(tx, ty)) return factory;
        }
        return null;
    }

    pub fn updateAll(self: *FactoryManager, dt: f32, empire_resources: []ResourceBundle) void {
        for (self.factories.items) |*factory| {
            if (factory.owner_id < empire_resources.len) {
                factory.update(dt, &empire_resources[factory.owner_id]);
            }
        }
    }

    pub fn draw(self: FactoryManager, bounds: anytype) void {
        for (self.factories.items) |factory| {
            const fx = factory.x;
            const fy = factory.y;
            const fw = @as(i32, factory.def.width);
            const fh = @as(i32, factory.def.height);

            if (fx + fw >= bounds.min_x and fx < bounds.max_x and
                fy + fh >= bounds.min_y and fy < bounds.max_y)
            {
                factory.draw();
            }
        }
    }

    pub fn getFactoriesForOwner(self: FactoryManager, owner_id: u8) []FactoryInstance {
        _ = self;
        _ = owner_id;
        // TODO: Return filtered list if needed
        return &.{};
    }
};
