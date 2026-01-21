const std = @import("std");
const rl = @import("raylib");
const terrain = @import("terrain.zig");

/// Attempt to emulate Ken Perlin's original noise algorithm from 1985 for very smooth gradient noise
pub const PerlinNoise = struct {
    perm: [512]u8,
    seed: u64,

    const gradients = [_][2]f32{
        .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 },
        .{ 0.7071, 0.7071 }, .{ -0.7071, 0.7071 }, .{ 0.7071, -0.7071 }, .{ -0.7071, -0.7071 },
    };

    pub fn init(seed: u64) PerlinNoise {
        var self = PerlinNoise{ .perm = undefined, .seed = seed };
        var prng = std.Random.DefaultPrng.init(seed);
        var rng = prng.random();

        for (0..256) |i| {
            self.perm[i] = @intCast(i);
        }

        // Fisher-Yates shuffle
        var i: usize = 255;
        while (i > 0) : (i -= 1) {
            const j = rng.uintLessThan(usize, i + 1);
            const tmp = self.perm[i];
            self.perm[i] = self.perm[j];
            self.perm[j] = tmp;
        }

        for (0..256) |idx| {
            self.perm[idx + 256] = self.perm[idx];
        }

        return self;
    }

    fn fade(t: f32) f32 {
        // 6t^5 - 15t^4 + 10t^3 (attempt to mimic Ken Perlin's improved version)
        return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
    }

    fn lerp(a: f32, b: f32, t: f32) f32 {
        return a + t * (b - a);
    }

    fn grad(_: *const PerlinNoise, hash: usize, x: f32, y: f32) f32 {
        const g = gradients[hash & 7];
        return g[0] * x + g[1] * y;
    }

    pub fn noise(self: *const PerlinNoise, x: f32, y: f32) f32 {
        const xi = @as(i32, @intFromFloat(@floor(x))) & 255;
        const yi = @as(i32, @intFromFloat(@floor(y))) & 255;

        const xf = x - @floor(x);
        const yf = y - @floor(y);

        const u = fade(xf);
        const v = fade(yf);

        const uxi = @as(usize, @intCast(xi));
        const uyi = @as(usize, @intCast(yi));

        const aa = self.perm[self.perm[uxi] + uyi];
        const ab = self.perm[self.perm[uxi] + uyi + 1];
        const ba = self.perm[self.perm[uxi + 1] + uyi];
        const bb = self.perm[self.perm[uxi + 1] + uyi + 1];

        const x1 = lerp(self.grad(aa, xf, yf), self.grad(ba, xf - 1, yf), u);
        const x2 = lerp(self.grad(ab, xf, yf - 1), self.grad(bb, xf - 1, yf - 1), u);

        return (lerp(x1, x2, v) + 1.0) / 2.0; // Normalize to 0-1
    }

    /// Attempt to emulate multi-octave fractal noise
    pub fn fractal(self: *const PerlinNoise, x: f32, y: f32, octaves: u32, lacunarity: f32, persistence: f32) f32 {
        var total: f32 = 0;
        var frequency: f32 = 1;
        var amplitude: f32 = 1;
        var max_value: f32 = 0;

        for (0..octaves) |_| {
            total += self.noise(x * frequency, y * frequency) * amplitude;
            max_value += amplitude;
            amplitude *= persistence;
            frequency *= lacunarity;
        }

        return total / max_value;
    }

    /// Attempt to emulate "ridged" noise for mountain ranges
    pub fn ridged(self: *const PerlinNoise, x: f32, y: f32, octaves: u32) f32 {
        var total: f32 = 0;
        var frequency: f32 = 1;
        var amplitude: f32 = 1;
        var max_value: f32 = 0;

        for (0..octaves) |_| {
            var n = self.noise(x * frequency, y * frequency);
            n = 1.0 - @abs(n * 2.0 - 1.0); // Create ridges
            n = n * n; // Sharpen the ridges
            total += n * amplitude;
            max_value += amplitude;
            amplitude *= 0.5;
            frequency *= 2.0;
        }

        return total / max_value;
    }
};

pub const BiomeType = enum {
    ocean,
    beach,
    grassland,
    forest,
    dense_forest,
    hills,
    mountains,
    snow_peaks,
    desert,
    wetland,
};

pub const MapConfig = struct {
    water_level: f32 = 0.35,
    beach_width: f32 = 0.03,
    mountain_threshold: f32 = 0.72,
    peak_threshold: f32 = 0.85,
    forest_moisture: f32 = 0.5,
    desert_moisture: f32 = 0.25,
    terrain_scale: f32 = 120.0,
    moisture_scale: f32 = 80.0,
    spawn_clear_radius: usize = 35,
    resource_richness: f32 = 1.0,
};

pub const MapGenerator = struct {
    allocator: std.mem.Allocator,
    perlin: PerlinNoise,
    prng: std.Random.DefaultPrng,
    config: MapConfig,

    elevation: ?[][]f32 = null,
    moisture: ?[][]f32 = null,
    width: usize = 0,
    height: usize = 0,

    pub fn init(allocator: std.mem.Allocator, seed: u64) MapGenerator {
        return .{
            .allocator = allocator,
            .perlin = PerlinNoise.init(seed),
            .prng = std.Random.DefaultPrng.init(seed *% 0x9E3779B97F4A7C15),
            .config = .{},
        };
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, seed: u64, config: MapConfig) MapGenerator {
        var gen = init(allocator, seed);
        gen.config = config;
        return gen;
    }

    pub fn generate(self: *MapGenerator, width: usize, height: usize) ![][]terrain.Tile {
        return self.generateSymmetric(width, height, 2);
    }

    pub fn generateSymmetric(self: *MapGenerator, width: usize, height: usize, num_players: u32) ![][]terrain.Tile {
        self.width = width;
        self.height = height;

        // Generate base heightmaps
        try self.generateElevation();
        try self.generateMoisture();

        // Apply island shaping and symmetry to heightmaps
        self.shapeContinent();
        self.carveRiverValleys();

        if (num_players == 2) {
            self.applyDiagonalSymmetryToMaps();
        } else if (num_players >= 4) {
            self.applyQuadrantSymmetryToMaps();
        }

        // Convert heightmaps to terrain
        const map = try self.allocateMap(width, height);
        self.populateTerrain(map);

        // Post-processing
        self.smoothCoastlines(map);
        self.addTerrainDetails(map);
        self.placeResources(map, num_players);
        self.clearSpawnAreas(map, num_players);

        // Cleanup intermediate data
        self.freeElevation();
        self.freeMoisture();

        return map;
    }

    fn allocateMap(self: *MapGenerator, width: usize, height: usize) ![][]terrain.Tile {
        const map = try self.allocator.alloc([]terrain.Tile, height);
        for (0..height) |y| {
            map[y] = try self.allocator.alloc(terrain.Tile, width);
        }
        return map;
    }

    fn generateElevation(self: *MapGenerator) !void {
        self.elevation = try self.allocator.alloc([]f32, self.height);
        for (0..self.height) |y| {
            self.elevation.?[y] = try self.allocator.alloc(f32, self.width);
        }

        const scale = self.config.terrain_scale;

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));

                // Base continental terrain
                const base = self.perlin.fractal(fx / scale, fy / scale, 6, 2.0, 0.5);

                // Mountain ridges
                const ridges = self.perlin.ridged(fx / (scale * 0.8), fy / (scale * 0.8), 4);

                // Combine: mostly base terrain with mountain ridges in high areas
                const ridge_influence = smoothstep(base, 0.5, 0.7);
                self.elevation.?[y][x] = base * (1.0 - ridge_influence * 0.4) + ridges * ridge_influence * 0.4;
            }
        }
    }

    fn generateMoisture(self: *MapGenerator) !void {
        self.moisture = try self.allocator.alloc([]f32, self.height);
        for (0..self.height) |y| {
            self.moisture.?[y] = try self.allocator.alloc(f32, self.width);
        }

        const scale = self.config.moisture_scale;

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));

                // Offset to get different pattern from elevation
                var m = self.perlin.fractal(fx / scale + 500, fy / scale + 500, 4, 2.0, 0.6);

                // Moisture increases near water
                const elev = self.elevation.?[y][x];
                if (elev < self.config.water_level + 0.1) {
                    m = m * 0.5 + 0.5;
                }

                self.moisture.?[y][x] = m;
            }
        }
    }

    fn shapeContinent(self: *MapGenerator) void {
        const fw = @as(f32, @floatFromInt(self.width));
        const fh = @as(f32, @floatFromInt(self.height));
        const cx = fw / 2.0;
        const cy = fh / 2.0;

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));

                // Distance from center (normalized)
                const dx = (fx - cx) / cx;
                const dy = (fy - cy) / cy;
                const dist = @sqrt(dx * dx + dy * dy);

                // Gradient falloff toward edges - creates island shape
                const falloff = 1.0 - smoothstep(dist, 0.6, 1.2);

                // Distance from corners (for spawn areas)
                const corner_tl = @sqrt(fx * fx + fy * fy) / fw;
                const corner_br = @sqrt((fw - fx) * (fw - fx) + (fh - fy) * (fh - fy)) / fw;
                const corner_tr = @sqrt((fw - fx) * (fw - fx) + fy * fy) / fw;
                const corner_bl = @sqrt(fx * fx + (fh - fy) * (fh - fy)) / fw;

                // Raise land near corners for spawn areas
                const spawn_boost_tl = (1.0 - smoothstep(corner_tl, 0.0, 0.3)) * 0.25;
                const spawn_boost_br = (1.0 - smoothstep(corner_br, 0.0, 0.3)) * 0.25;
                const spawn_boost_tr = (1.0 - smoothstep(corner_tr, 0.0, 0.3)) * 0.25;
                const spawn_boost_bl = (1.0 - smoothstep(corner_bl, 0.0, 0.3)) * 0.25;
                const spawn_boost = @max(@max(spawn_boost_tl, spawn_boost_br), @max(spawn_boost_tr, spawn_boost_bl));

                self.elevation.?[y][x] = self.elevation.?[y][x] * falloff + spawn_boost;
            }
        }
    }

    fn carveRiverValleys(self: *MapGenerator) void {
        const fw = @as(f32, @floatFromInt(self.width));
        const fh = @as(f32, @floatFromInt(self.height));

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));

                // Create river-like valleys using domain-warped lines
                const warp = self.perlin.noise(fx / 60.0, fy / 60.0) * 30.0;

                // Horizontal river
                const river_h_dist = @abs(fy - fh * 0.5 + warp);
                const river_h = 1.0 - smoothstep(river_h_dist, 0.0, 25.0);

                // Vertical river
                const river_v_dist = @abs(fx - fw * 0.5 + warp);
                const river_v = 1.0 - smoothstep(river_v_dist, 0.0, 25.0);

                // Carve valleys where rivers flow
                const river_depth = @max(river_h, river_v) * 0.15;
                self.elevation.?[y][x] -= river_depth;

                // Increase moisture near rivers
                self.moisture.?[y][x] = @min(1.0, self.moisture.?[y][x] + @max(river_h, river_v) * 0.3);
            }
        }
    }

    fn applyDiagonalSymmetryToMaps(self: *MapGenerator) void {
        for (0..self.height) |y| {
            for (y..self.width) |x| {
                const avg_e = (self.elevation.?[y][x] + self.elevation.?[x][y]) / 2.0;
                const avg_m = (self.moisture.?[y][x] + self.moisture.?[x][y]) / 2.0;
                self.elevation.?[y][x] = avg_e;
                self.elevation.?[x][y] = avg_e;
                self.moisture.?[y][x] = avg_m;
                self.moisture.?[x][y] = avg_m;
            }
        }
    }

    fn applyQuadrantSymmetryToMaps(self: *MapGenerator) void {
        const half_w = self.width / 2;
        const half_h = self.height / 2;

        for (0..half_h) |y| {
            for (0..half_w) |x| {
                const e = self.elevation.?[y][x];
                const m = self.moisture.?[y][x];

                self.elevation.?[y][self.width - 1 - x] = e;
                self.elevation.?[self.height - 1 - y][x] = e;
                self.elevation.?[self.height - 1 - y][self.width - 1 - x] = e;

                self.moisture.?[y][self.width - 1 - x] = m;
                self.moisture.?[self.height - 1 - y][x] = m;
                self.moisture.?[self.height - 1 - y][self.width - 1 - x] = m;
            }
        }
    }

    fn populateTerrain(self: *MapGenerator, map: [][]terrain.Tile) void {
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const elev = self.elevation.?[y][x];
                const moist = self.moisture.?[y][x];
                const biome = self.getBiome(elev, moist);
                map[y][x] = .{
                    .terrain = biomeToTerrain(biome),
                    .resources = null,
                };
            }
        }
    }

    fn getBiome(self: *MapGenerator, elevation: f32, moisture: f32) BiomeType {
        const cfg = self.config;

        if (elevation < cfg.water_level - 0.05) return .ocean;
        if (elevation < cfg.water_level) return .ocean;
        if (elevation < cfg.water_level + cfg.beach_width) return .beach;

        if (elevation > cfg.peak_threshold) return .snow_peaks;
        if (elevation > cfg.mountain_threshold) return .mountains;
        if (elevation > cfg.mountain_threshold - 0.08) return .hills;

        // Mid elevations: biome depends on moisture
        if (moisture < cfg.desert_moisture) return .desert;
        if (moisture > cfg.forest_moisture + 0.2) return .dense_forest;
        if (moisture > cfg.forest_moisture) return .forest;
        if (moisture > cfg.forest_moisture - 0.1 and elevation < cfg.water_level + 0.15) return .wetland;

        return .grassland;
    }

    fn biomeToTerrain(biome: BiomeType) terrain.TerrainType {
        return switch (biome) {
            .ocean => .deep_water,
            .beach => .sand,
            .grassland => .grass,
            .forest => .forest,
            .dense_forest => .forest,
            .hills => .hills,
            .mountains => .mountains,
            .snow_peaks => .mountains,
            .desert => .sand,
            .wetland => .shallow_water,
        };
    }

    fn smoothCoastlines(self: *MapGenerator, map: [][]terrain.Tile) void {
        // Add shallow water between deep water and land
        for (1..self.height - 1) |y| {
            for (1..self.width - 1) |x| {
                if (map[y][x].terrain != .deep_water) continue;

                var land_neighbor = false;
                for ([_]i8{ -1, 0, 1 }) |dy| {
                    for ([_]i8{ -1, 0, 1 }) |dx| {
                        if (dx == 0 and dy == 0) continue;
                        const nx = @as(usize, @intCast(@as(i32, @intCast(x)) + dx));
                        const ny = @as(usize, @intCast(@as(i32, @intCast(y)) + dy));
                        const t = map[ny][nx].terrain;
                        if (t != .deep_water and t != .shallow_water) {
                            land_neighbor = true;
                        }
                    }
                }

                if (land_neighbor) {
                    map[y][x].terrain = .shallow_water;
                }
            }
        }
    }

    fn addTerrainDetails(self: *MapGenerator, map: [][]terrain.Tile) void {
        var rng = self.prng.random();

        for (2..self.height - 2) |y| {
            for (2..self.width - 2) |x| {
                const current = map[y][x].terrain;

                // Add scattered trees in grassland near forests
                if (current == .grass) {
                    var forest_neighbors: u32 = 0;
                    for ([_]i8{ -1, 0, 1 }) |dy| {
                        for ([_]i8{ -1, 0, 1 }) |dx| {
                            const nx = @as(usize, @intCast(@as(i32, @intCast(x)) + dx));
                            const ny = @as(usize, @intCast(@as(i32, @intCast(y)) + dy));
                            if (map[ny][nx].terrain == .forest) forest_neighbors += 1;
                        }
                    }
                    if (forest_neighbors >= 2 and rng.float(f32) < 0.15) {
                        map[y][x].terrain = .forest;
                    }
                }

                // Add hills at base of mountains
                if (current == .grass) {
                    var mountain_neighbors: u32 = 0;
                    for ([_]i8{ -1, 0, 1 }) |dy| {
                        for ([_]i8{ -1, 0, 1 }) |dx| {
                            const nx = @as(usize, @intCast(@as(i32, @intCast(x)) + dx));
                            const ny = @as(usize, @intCast(@as(i32, @intCast(y)) + dy));
                            if (map[ny][nx].terrain == .mountains) mountain_neighbors += 1;
                        }
                    }
                    if (mountain_neighbors >= 1 and rng.float(f32) < 0.4) {
                        map[y][x].terrain = .hills;
                    }
                }
            }
        }
    }

    fn placeResources(self: *MapGenerator, map: [][]terrain.Tile, num_players: u32) void {
        var rng = self.prng.random();
        const richness = self.config.resource_richness;

        const fw = @as(f32, @floatFromInt(self.width));
        const fh = @as(f32, @floatFromInt(self.height));

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const tile = &map[y][x];
                if (!tile.terrain.isWalkable()) continue;

                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));

                // Resource noise for clustering
                const resource_noise = self.perlin.noise(fx / 25.0 + 1000, fy / 25.0 + 1000);

                // Gold near center (contested)
                const center_dist = @sqrt((fx - fw / 2) * (fx - fw / 2) + (fy - fh / 2) * (fy - fh / 2)) / fw;
                if (center_dist < 0.2 and resource_noise > 0.65 and rng.float(f32) < 0.03 * richness) {
                    tile.resources = .gold;
                    continue;
                }

                // Iron near mountains/hills
                if ((tile.terrain == .hills or self.hasAdjacentTerrain(map, x, y, .mountains)) and
                    resource_noise > 0.6 and rng.float(f32) < 0.04 * richness)
                {
                    tile.resources = .iron;
                    continue;
                }

                // Stone in hills
                if (tile.terrain == .hills and resource_noise > 0.55 and rng.float(f32) < 0.05 * richness) {
                    tile.resources = .stone;
                    continue;
                }

                // Wood in forests
                if (tile.terrain == .forest and resource_noise > 0.5 and rng.float(f32) < 0.06 * richness) {
                    tile.resources = .wood;
                    continue;
                }
            }
        }

        // Ensure each spawn corner has starting resources
        self.ensureSpawnResources(map, num_players);
    }

    fn hasAdjacentTerrain(self: *MapGenerator, map: [][]terrain.Tile, x: usize, y: usize, t: terrain.TerrainType) bool {
        _ = self;
        if (x == 0 or y == 0 or x >= map[0].len - 1 or y >= map.len - 1) return false;

        for ([_]i8{ -1, 0, 1 }) |dy| {
            for ([_]i8{ -1, 0, 1 }) |dx| {
                if (dx == 0 and dy == 0) continue;
                const nx = @as(usize, @intCast(@as(i32, @intCast(x)) + dx));
                const ny = @as(usize, @intCast(@as(i32, @intCast(y)) + dy));
                if (map[ny][nx].terrain == t) return true;
            }
        }
        return false;
    }

    fn ensureSpawnResources(self: *MapGenerator, map: [][]terrain.Tile, num_players: u32) void {
        const spawn_positions = self.getSpawnPositions(num_players);

        for (spawn_positions) |spawn| {
            if (spawn[0] == 0 and spawn[1] == 0) continue;

            var rng = self.prng.random();
            const radius = self.config.spawn_clear_radius;

            // Place guaranteed starting resources around each spawn
            var wood_placed: u32 = 0;
            var stone_placed: u32 = 0;
            var gold_placed: u32 = 0;

            const target_wood: u32 = 4;
            const target_stone: u32 = 3;
            const target_gold: u32 = 2;

            for (0..200) |_| {
                const angle = rng.float(f32) * std.math.pi * 2.0;
                const dist = @as(f32, @floatFromInt(radius / 2)) + rng.float(f32) * @as(f32, @floatFromInt(radius / 2));

                const rx = @as(i32, @intCast(spawn[0])) + @as(i32, @intFromFloat(@cos(angle) * dist));
                const ry = @as(i32, @intCast(spawn[1])) + @as(i32, @intFromFloat(@sin(angle) * dist));

                if (rx < 0 or ry < 0 or rx >= self.width or ry >= self.height) continue;

                const ux = @as(usize, @intCast(rx));
                const uy = @as(usize, @intCast(ry));

                if (!map[uy][ux].terrain.isWalkable() or map[uy][ux].resources != null) continue;

                if (wood_placed < target_wood and map[uy][ux].terrain == .forest) {
                    map[uy][ux].resources = .wood;
                    wood_placed += 1;
                } else if (stone_placed < target_stone and (map[uy][ux].terrain == .hills or map[uy][ux].terrain == .grass)) {
                    map[uy][ux].resources = .stone;
                    stone_placed += 1;
                } else if (gold_placed < target_gold and map[uy][ux].terrain == .grass) {
                    map[uy][ux].resources = .gold;
                    gold_placed += 1;
                }

                if (wood_placed >= target_wood and stone_placed >= target_stone and gold_placed >= target_gold) break;
            }
        }
    }

    fn clearSpawnAreas(self: *MapGenerator, map: [][]terrain.Tile, num_players: u32) void {
        const spawn_positions = self.getSpawnPositions(num_players);
        const radius = self.config.spawn_clear_radius;
        const inner_radius = radius / 2;

        for (spawn_positions) |spawn| {
            if (spawn[0] == 0 and spawn[1] == 0) continue;

            for (0..self.height) |y| {
                for (0..self.width) |x| {
                    const dx = @as(i32, @intCast(x)) - @as(i32, @intCast(spawn[0]));
                    const dy = @as(i32, @intCast(y)) - @as(i32, @intCast(spawn[1]));
                    const dist_sq = @as(u32, @intCast(dx * dx + dy * dy));

                    if (dist_sq < inner_radius * inner_radius) {
                        // Inner zone: guaranteed clear grass
                        map[y][x].terrain = .grass;
                        map[y][x].resources = null;
                    } else if (dist_sq < radius * radius) {
                        // Outer zone: remove impassable terrain
                        if (!map[y][x].terrain.isWalkable()) {
                            map[y][x].terrain = .grass;
                        }
                    }
                }
            }
        }
    }

    fn getSpawnPositions(self: *MapGenerator, num_players: u32) [4][2]usize {
        const margin = self.config.spawn_clear_radius;

        if (num_players >= 4) {
            return .{
                .{ margin, margin },
                .{ self.width - margin - 1, margin },
                .{ margin, self.height - margin - 1 },
                .{ self.width - margin - 1, self.height - margin - 1 },
            };
        } else {
            return .{
                .{ margin, margin },
                .{ self.width - margin - 1, self.height - margin - 1 },
                .{ 0, 0 },
                .{ 0, 0 },
            };
        }
    }

    fn freeElevation(self: *MapGenerator) void {
        if (self.elevation) |elev| {
            for (elev) |row| {
                self.allocator.free(row);
            }
            self.allocator.free(elev);
            self.elevation = null;
        }
    }

    fn freeMoisture(self: *MapGenerator) void {
        if (self.moisture) |moist| {
            for (moist) |row| {
                self.allocator.free(row);
            }
            self.allocator.free(moist);
            self.moisture = null;
        }
    }

    pub fn deinit(self: *MapGenerator, map: [][]terrain.Tile) void {
        for (map) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(map);
        self.freeElevation();
        self.freeMoisture();
    }
};

fn smoothstep(x: f32, edge0: f32, edge1: f32) f32 {
    const t = std.math.clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
