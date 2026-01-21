const std = @import("std");
const rl = @import("raylib");
const resources = @import("resources.zig");
const constants = @import("constants.zig");

pub const ResourceBundle = resources.ResourceBundle;
pub const ResourceType = resources.ResourceType;

pub const Empire = struct {
    id: u8,
    name: []const u8,
    color: rl.Color,
    resources: ResourceBundle,
    spawn_x: i32,
    spawn_y: i32,

    pub fn init(id: u8, name: []const u8, color: rl.Color, spawn_x: i32, spawn_y: i32) Empire {
        return .{
            .id = id,
            .name = name,
            .color = color,
            .resources = .{},
            .spawn_x = spawn_x,
            .spawn_y = spawn_y,
        };
    }

    pub fn giveResources(self: *Empire, bundle: ResourceBundle) void {
        self.resources.addBundle(bundle);
    }

    pub fn giveResource(self: *Empire, resource: ResourceType, amount: f32) void {
        self.resources.add(resource, amount);
    }

    pub fn canAfford(self: Empire, cost: ResourceBundle) bool {
        return self.resources.canAfford(cost);
    }

    pub fn spend(self: *Empire, cost: ResourceBundle) bool {
        return self.resources.subtractBundle(cost);
    }
};

pub const EmpireManager = struct {
    empires: std.ArrayList(Empire),
    local_player_id: u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) EmpireManager {
        return .{
            .empires = .empty,
            .local_player_id = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *EmpireManager) void {
        self.empires.deinit(self.allocator);
    }

    pub fn addEmpire(self: *EmpireManager, name: []const u8, color: rl.Color, spawn_x: i32, spawn_y: i32) !*Empire {
        const id = @as(u8, @intCast(self.empires.items.len));
        try self.empires.append(self.allocator, Empire.init(id, name, color, spawn_x, spawn_y));
        return &self.empires.items[self.empires.items.len - 1];
    }

    pub fn getEmpire(self: *EmpireManager, id: u8) ?*Empire {
        if (id < self.empires.items.len) {
            return &self.empires.items[id];
        }
        return null;
    }

    pub fn getLocalPlayer(self: *EmpireManager) ?*Empire {
        return self.getEmpire(self.local_player_id);
    }

    pub fn getResourceSlice(self: *EmpireManager) []ResourceBundle {
        // Create a slice of resource bundles for factory updates
        var result = self.allocator.alloc(ResourceBundle, self.empires.items.len) catch return &.{};
        for (self.empires.items, 0..) |empire, i| {
            result[i] = empire.resources;
        }
        return result;
    }

    pub fn syncResourcesBack(self: *EmpireManager, resource_slice: []ResourceBundle) void {
        for (self.empires.items, 0..) |*empire, i| {
            if (i < resource_slice.len) {
                empire.resources = resource_slice[i];
            }
        }
        self.allocator.free(resource_slice);
    }
};

pub const EMPIRE_COLORS = struct {
    pub const RED = rl.Color.init(200, 60, 60, 255);
    pub const BLUE = rl.Color.init(60, 80, 200, 255);
    pub const GREEN = rl.Color.init(60, 180, 60, 255);
    pub const YELLOW = rl.Color.init(220, 200, 60, 255);
    pub const PURPLE = rl.Color.init(160, 60, 180, 255);
    pub const ORANGE = rl.Color.init(230, 140, 40, 255);
    pub const CYAN = rl.Color.init(60, 200, 200, 255);
    pub const PINK = rl.Color.init(230, 120, 180, 255);
};

pub const STARTING_RESOURCES = ResourceBundle{
    .gold = 50,
    .iron = 100,
    .wood = 200,
    .stone = 150,
    .coins = 500,
};
