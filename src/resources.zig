const std = @import("std");

pub const ResourceType = enum {
    gold,
    iron,
    wood,
    stone,
    coins,

    pub fn getName(self: ResourceType) []const u8 {
        return switch (self) {
            .gold => "Gold",
            .iron => "Iron",
            .wood => "Wood",
            .stone => "Stone",
            .coins => "Coins",
        };
    }
};

pub const ResourceBundle = struct {
    gold: f32 = 0,
    iron: f32 = 0,
    wood: f32 = 0,
    stone: f32 = 0,
    coins: f32 = 0,

    pub fn get(self: ResourceBundle, resource: ResourceType) f32 {
        return switch (resource) {
            .gold => self.gold,
            .iron => self.iron,
            .wood => self.wood,
            .stone => self.stone,
            .coins => self.coins,
        };
    }

    pub fn set(self: *ResourceBundle, resource: ResourceType, value: f32) void {
        switch (resource) {
            .gold => self.gold = value,
            .iron => self.iron = value,
            .wood => self.wood = value,
            .stone => self.stone = value,
            .coins => self.coins = value,
        }
    }

    pub fn add(self: *ResourceBundle, resource: ResourceType, amount: f32) void {
        switch (resource) {
            .gold => self.gold += amount,
            .iron => self.iron += amount,
            .wood => self.wood += amount,
            .stone => self.stone += amount,
            .coins => self.coins += amount,
        }
    }

    pub fn subtract(self: *ResourceBundle, resource: ResourceType, amount: f32) bool {
        const current = self.get(resource);
        if (current >= amount) {
            self.add(resource, -amount);
            return true;
        }
        return false;
    }

    pub fn addBundle(self: *ResourceBundle, other: ResourceBundle) void {
        self.gold += other.gold;
        self.iron += other.iron;
        self.wood += other.wood;
        self.stone += other.stone;
        self.coins += other.coins;
    }

    pub fn canAfford(self: ResourceBundle, cost: ResourceBundle) bool {
        return self.gold >= cost.gold and
            self.iron >= cost.iron and
            self.wood >= cost.wood and
            self.stone >= cost.stone and
            self.coins >= cost.coins;
    }

    pub fn subtractBundle(self: *ResourceBundle, cost: ResourceBundle) bool {
        if (!self.canAfford(cost)) return false;
        self.gold -= cost.gold;
        self.iron -= cost.iron;
        self.wood -= cost.wood;
        self.stone -= cost.stone;
        self.coins -= cost.coins;
        return true;
    }

    pub fn scale(self: ResourceBundle, factor: f32) ResourceBundle {
        return .{
            .gold = self.gold * factor,
            .iron = self.iron * factor,
            .wood = self.wood * factor,
            .stone = self.stone * factor,
            .coins = self.coins * factor,
        };
    }
};

pub const ResourceRate = struct {
    resource: ResourceType,
    per_second: f32,
};
