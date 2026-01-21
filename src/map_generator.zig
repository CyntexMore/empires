const std = @import("std");
const rl = @import("raylib");
const constants = @import("constants.zig");
const terrain = @import("terrain.zig");

pub const NoiseGenerator = struct {
    seed: u64,
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) NoiseGenerator {
        return .{
            .seed = seed,
            .prng = std.Random.DefaultPrng.init(seed),
        };
    }

    pub fn random(self: *NoiseGenerator) std.Random {
        return self.prng.random();
    }

    fn hash2D(self: *NoiseGenerator, x: i32, y: i32) f32 {
        const n = x *% 374761393 +% y *% 668265263;
        const h = @as(u32, @bitCast(n)) ^ @as(u32, @truncate(self.seed));
        return @as(f32, @floatFromInt(h & 0x7fffffff)) / @as(f32, @floatFromInt(0x7fffffff));
    }

    fn smoothstep(t: f32) f32 {
        return t * t * (3.0 - 2.0 * t);
    }

    fn noise2D(self: *NoiseGenerator, x: f32, y: f32) f32 {
        const x0 = @floor(x);
        const y0 = @floor(y);

        const sx = x - x0;
        const sy = y - y0;

        const ix0 = @as(i32, @intFromFloat(x0));
        const iy0 = @as(i32, @intFromFloat(y0));

        const n00 = self.hash2D(ix0, iy0);
        const n10 = self.hash2D(ix0 + 1, iy0);
        const n01 = self.hash2D(ix0, iy0 + 1);
        const n11 = self.hash2D(ix0 + 1, iy0 + 1);

        const tx = smoothstep(sx);
        const ty = smoothstep(sy);

        const nx0 = n00 * (1.0 - tx) + n10 * tx;
        const nx1 = n01 * (1.0 - tx) + n11 * tx;

        return nx0 * (1.0 - ty) + nx1 * ty;
    }

    pub fn fbm(self: *NoiseGenerator, x: f32, y: f32, octaves: u32, persistence: f32) f32 {
        var total: f32 = 0.0;
        var frequency: f32 = 1.0;
        var amplitude: f32 = 1.0;
        var max_value: f32 = 0.0;

        for (0..octaves) |_| {
            total += self.noise2D(x * frequency, y * frequency) * amplitude;
            max_value += amplitude;
            amplitude *= persistence;
            frequency *= 2.0;
        }

        return total / max_value;
    }
};

pub const MapGenerator = struct {
    allocator: std.mem.Allocator,
    noise: NoiseGenerator,

    pub fn init(allocator: std.mem.Allocator, seed: u64) MapGenerator {
        return .{
            .allocator = allocator,
            .noise = NoiseGenerator.init(seed),
        };
    }

    pub fn generate(self: *MapGenerator, width: usize, height: usize) ![][]terrain.Tile {
        const map = try self.allocator.alloc([]terrain.Tile, height);
        for (0..height) |y| {
            map[y] = try self.allocator.alloc(terrain.Tile, width);
        }

        for (0..height) |y| {
            for (0..width) |x| {
                map[y][x] = .{ .terrain = .grass, .resources = null };
            }
        }

        return map;
    }

    pub fn generateSymmetric(self: *MapGenerator, width: usize, height: usize, num_players: u32) ![][]terrain.Tile {
        const map = try self.allocator.alloc([]terrain.Tile, height);
        for (0..height) |y| {
            map[y] = try self.allocator.alloc(terrain.Tile, width);
        }

        const fw = @as(f32, @floatFromInt(width));
        const fh = @as(f32, @floatFromInt(height));
        const center_x = fw / 2.0;
        const center_y = fh / 2.0;

        for (0..height) |y| {
            for (0..width) |x| {
                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));

                const dx = (fx - center_x) / center_x;
                const dy = (fy - center_y) / center_y;
                const dist_from_center = @sqrt(dx * dx + dy * dy);

                const dist_corner_tl = @sqrt(fx * fx + fy * fy) / fw;
                const dist_corner_br = @sqrt((fw - fx) * (fw - fx) + (fh - fy) * (fh - fy)) / fw;
                const min_corner_dist = @min(dist_corner_tl, dist_corner_br);

                const base_noise = self.noise.fbm(fx / 80.0, fy / 80.0, 4, 0.5);

                var terrain_type: terrain.TerrainType = .grass;

                if (min_corner_dist < 0.15) {
                    terrain_type = .grass;
                }
                else if (dist_from_center < 0.25) {
                    const central_noise = self.noise.fbm(fx / 30.0 + 50.0, fy / 30.0 + 50.0, 3, 0.6);
                    if (central_noise > 0.65) {
                        terrain_type = .hills;
                    } else if (central_noise < 0.35) {
                        terrain_type = .forest;
                    } else {
                        terrain_type = .grass;
                    }
                }
                else {
                    terrain_type = self.generateMainTerrain(fx, fy, fw, fh, base_noise, dist_from_center);
                }

                map[y][x] = .{ .terrain = terrain_type, .resources = null };
            }
        }

        self.createMountainBarriers(map, width, height);

        self.createWaterFeatures(map, width, height);

        self.addForestPatches(map, width, height);

        if (num_players == 2) {
            self.applyDiagonalSymmetry(map, width, height);
        } else if (num_players == 4) {
            self.applyQuadrantSymmetry(map, width, height);
        }

        self.smoothTerrain(map, width, height);
        self.smoothTerrain(map, width, height);

        self.placeStrategicResources(map, width, height);

        self.clearSpawnZones(map, width, height, num_players);

        return map;
    }

    fn generateMainTerrain(self: *MapGenerator, fx: f32, fy: f32, fw: f32, fh: f32, base_noise: f32, dist_from_center: f32) terrain.TerrainType {
        _ = fw;
        _ = fh;
        _ = dist_from_center;

        const detail_noise = self.noise.fbm(fx / 40.0 + 100.0, fy / 40.0 + 100.0, 3, 0.5);

        const combined = base_noise * 0.6 + detail_noise * 0.4;

        if (combined > 0.72) {
            return .hills;
        } else if (combined > 0.58) {
            return .forest;
        } else if (combined < 0.25) {
            return .sand;
        }

        return .grass;
    }

    fn createMountainBarriers(self: *MapGenerator, map: [][]terrain.Tile, width: usize, height: usize) void {
        const fw = @as(f32, @floatFromInt(width));
        const fh = @as(f32, @floatFromInt(height));

        for (0..height) |y| {
            for (0..width) |x| {
                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));

                const diag_dist = @abs(fx - fy) / @sqrt(2.0);

                const ridge_noise = self.noise.fbm(fx / 60.0 + 200.0, fy / 60.0 + 200.0, 2, 0.5);
                const ridge_width = 15.0 + ridge_noise * 20.0;

                const norm_pos = (fx + fy) / (fw + fh);
                const in_ridge_zone = norm_pos > 0.25 and norm_pos < 0.75;

                if (diag_dist < ridge_width and in_ridge_zone) {
                    const gap_noise = self.noise.fbm(fx / 25.0, fy / 25.0, 2, 0.5);
                    const gap_threshold = 0.55 - (diag_dist / ridge_width) * 0.3;

                    if (gap_noise > gap_threshold) {
                        if (map[y][x].terrain == .grass) {
                            map[y][x].terrain = .sand;
                        }
                    } else {
                        map[y][x].terrain = .mountains;
                    }
                }

                const anti_diag_dist = @abs((fw - fx) - fy) / @sqrt(2.0);
                const anti_norm_pos = ((fw - fx) + fy) / (fw + fh);
                const in_anti_ridge_zone = anti_norm_pos > 0.25 and anti_norm_pos < 0.75;

                if (anti_diag_dist < ridge_width * 0.7 and in_anti_ridge_zone) {
                    const gap_noise = self.noise.fbm(fx / 25.0 + 500.0, fy / 25.0 + 500.0, 2, 0.5);
                    if (gap_noise < 0.5) {
                        map[y][x].terrain = .mountains;
                    }
                }
            }
        }
    }

    fn createWaterFeatures(self: *MapGenerator, map: [][]terrain.Tile, width: usize, height: usize) void {
        const fw = @as(f32, @floatFromInt(width));
        const fh = @as(f32, @floatFromInt(height));

        for (0..height) |y| {
            for (0..width) |x| {
                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));

                if (map[y][x].terrain == .mountains) continue;

                const edge_dist_x = @min(fx, fw - fx);
                const edge_dist_y = @min(fy, fh - fy);

                const corner_dist_tl = @sqrt(fx * fx + fy * fy);
                const corner_dist_tr = @sqrt((fw - fx) * (fw - fx) + fy * fy);
                const corner_dist_bl = @sqrt(fx * fx + (fh - fy) * (fh - fy));
                const corner_dist_br = @sqrt((fw - fx) * (fw - fx) + (fh - fy) * (fh - fy));
                const min_corner = @min(@min(corner_dist_tl, corner_dist_tr), @min(corner_dist_bl, corner_dist_br));

                if (min_corner > fw * 0.3) {
                    const water_noise = self.noise.fbm(fx / 50.0 + 300.0, fy / 50.0 + 300.0, 3, 0.5);

                    if (edge_dist_y < fw * 0.15 and water_noise > 0.55) {
                        if (water_noise > 0.65) {
                            map[y][x].terrain = .deep_water;
                        } else {
                            map[y][x].terrain = .shallow_water;
                        }
                    }
                    else if (edge_dist_x < fw * 0.15 and water_noise > 0.55) {
                        if (water_noise > 0.65) {
                            map[y][x].terrain = .deep_water;
                        } else {
                            map[y][x].terrain = .shallow_water;
                        }
                    }
                }
            }
        }

        self.addWaterShores(map, width, height);
    }

    fn addWaterShores(self: *MapGenerator, map: [][]terrain.Tile, width: usize, height: usize) void {
        _ = self;

        for (1..height - 1) |y| {
            for (1..width - 1) |x| {
                if (map[y][x].terrain == .deep_water) continue;
                if (map[y][x].terrain == .mountains) continue;

                const offsets = [_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } };
                var adjacent_to_deep = false;

                for (offsets) |offset| {
                    const nx = @as(usize, @intCast(@as(i32, @intCast(x)) + offset[0]));
                    const ny = @as(usize, @intCast(@as(i32, @intCast(y)) + offset[1]));

                    if (map[ny][nx].terrain == .deep_water) {
                        adjacent_to_deep = true;
                        break;
                    }
                }

                if (adjacent_to_deep) {
                    map[y][x].terrain = .shallow_water;
                }
            }
        }
    }

    fn addForestPatches(self: *MapGenerator, map: [][]terrain.Tile, width: usize, height: usize) void {
        const fw = @as(f32, @floatFromInt(width));
        const fh = @as(f32, @floatFromInt(height));

        for (0..height) |y| {
            for (0..width) |x| {
                if (map[y][x].terrain != .grass) continue;

                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));

                const corner_dist = @min(
                    @sqrt(fx * fx + fy * fy),
                    @sqrt((fw - fx) * (fw - fx) + (fh - fy) * (fh - fy)),
                );

                if (corner_dist < fw * 0.18) continue;

                const forest_noise = self.noise.fbm(fx / 35.0 + 400.0, fy / 35.0 + 400.0, 3, 0.6);

                if (forest_noise > 0.62) {
                    map[y][x].terrain = .forest;
                }
            }
        }
    }

    fn applyDiagonalSymmetry(self: *MapGenerator, map: [][]terrain.Tile, width: usize, height: usize) void {
        _ = self;

        for (0..height) |y| {
            for (y..width) |x| {
                map[x][y] = map[y][x];
            }
        }
    }

    fn applyQuadrantSymmetry(self: *MapGenerator, map: [][]terrain.Tile, width: usize, height: usize) void {
        _ = self;

        const half_w = width / 2;
        const half_h = height / 2;

        for (0..half_h) |y| {
            for (0..half_w) |x| {
                const tile = map[y][x];
                map[y][width - 1 - x] = tile;
                map[height - 1 - y][x] = tile;
                map[height - 1 - y][width - 1 - x] = tile;
            }
        }
    }

    fn smoothTerrain(self: *MapGenerator, map: [][]terrain.Tile, width: usize, height: usize) void {
        _ = self;

        for (2..height - 2) |y| {
            for (2..width - 2) |x| {
                const current = map[y][x].terrain;

                var same_count: u32 = 0;
                var grass_count: u32 = 0;

                const offsets = [_][2]i32{
                    .{ -1, 0 },  .{ 1, 0 },  .{ 0, -1 }, .{ 0, 1 },
                    .{ -1, -1 }, .{ 1, -1 }, .{ -1, 1 }, .{ 1, 1 },
                };

                for (offsets) |offset| {
                    const nx = @as(usize, @intCast(@as(i32, @intCast(x)) + offset[0]));
                    const ny = @as(usize, @intCast(@as(i32, @intCast(y)) + offset[1]));
                    const neighbor = map[ny][nx].terrain;

                    if (neighbor == current) same_count += 1;
                    if (neighbor == .grass) grass_count += 1;
                }

                if (same_count <= 1 and current != .grass and current != .mountains) {
                    if (grass_count >= 5) {
                        map[y][x].terrain = .grass;
                    }
                }

                if (current == .grass) {
                    var mountain_count: u32 = 0;
                    for (offsets) |offset| {
                        const nx = @as(usize, @intCast(@as(i32, @intCast(x)) + offset[0]));
                        const ny = @as(usize, @intCast(@as(i32, @intCast(y)) + offset[1]));
                        if (map[ny][nx].terrain == .mountains) mountain_count += 1;
                    }
                    if (mountain_count >= 6) {
                        map[y][x].terrain = .mountains;
                    }
                }
            }
        }
    }

    fn placeStrategicResources(self: *MapGenerator, map: [][]terrain.Tile, width: usize, height: usize) void {
        const fw = @as(f32, @floatFromInt(width));
        const fh = @as(f32, @floatFromInt(height));
        const center_x = fw / 2.0;
        const center_y = fh / 2.0;

        var rng = self.noise.random();

        self.placeResourceInZone(map, width, height, .gold, center_x, center_y, fw * 0.15, 8, &rng);

        self.placeResourceInZone(map, width, height, .gold, fw * 0.25, fh * 0.25, fw * 0.08, 4, &rng);
        self.placeResourceInZone(map, width, height, .gold, fw * 0.75, fh * 0.75, fw * 0.08, 4, &rng);

        self.placeResourceInZone(map, width, height, .iron, fw * 0.12, fh * 0.12, fw * 0.08, 6, &rng);
        self.placeResourceInZone(map, width, height, .iron, fw * 0.88, fh * 0.88, fw * 0.08, 6, &rng);

        self.placeResourceInZone(map, width, height, .stone, fw * 0.35, fh * 0.35, fw * 0.12, 8, &rng);
        self.placeResourceInZone(map, width, height, .stone, fw * 0.65, fh * 0.65, fw * 0.12, 8, &rng);

        for (0..height) |y| {
            for (0..width) |x| {
                if (map[y][x].terrain == .forest and map[y][x].resources == null) {
                    if (rng.float(f32) < 0.08) {
                        map[y][x].resources = .wood;
                    }
                }
            }
        }
    }

    fn placeResourceInZone(
        self: *MapGenerator,
        map: [][]terrain.Tile,
        width: usize,
        height: usize,
        resource: terrain.ResourceType,
        center_x: f32,
        center_y: f32,
        radius: f32,
        count: u32,
        rng: *std.Random,
    ) void {
        _ = self;

        var placed: u32 = 0;
        var attempts: u32 = 0;

        while (placed < count and attempts < count * 50) {
            attempts += 1;

            const angle = rng.float(f32) * std.math.pi * 2.0;
            const dist = rng.float(f32) * radius;

            const fx = center_x + @cos(angle) * dist;
            const fy = center_y + @sin(angle) * dist;

            if (fx < 0 or fx >= @as(f32, @floatFromInt(width)) or fy < 0 or fy >= @as(f32, @floatFromInt(height))) {
                continue;
            }

            const x = @as(usize, @intFromFloat(fx));
            const y = @as(usize, @intFromFloat(fy));

            if (map[y][x].terrain.isWalkable() and map[y][x].resources == null) {
                map[y][x].resources = resource;
                placed += 1;

                const offsets = [_][2]i32{ .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ -1, 0 }, .{ 0, -1 } };
                for (offsets) |offset| {
                    if (rng.float(f32) < 0.4) {
                        const nx = @as(i32, @intCast(x)) + offset[0];
                        const ny = @as(i32, @intCast(y)) + offset[1];

                        if (nx >= 0 and nx < width and ny >= 0 and ny < height) {
                            const ux = @as(usize, @intCast(nx));
                            const uy = @as(usize, @intCast(ny));
                            if (map[uy][ux].terrain.isWalkable() and map[uy][ux].resources == null) {
                                map[uy][ux].resources = resource;
                            }
                        }
                    }
                }
            }
        }
    }

    fn clearSpawnZones(self: *MapGenerator, map: [][]terrain.Tile, width: usize, height: usize, num_players: u32) void {
        _ = self;

        const spawn_radius: usize = 40;

        const spawn_points = if (num_players == 4)
            [_][2]usize{ .{ spawn_radius, spawn_radius }, .{ width - spawn_radius - 1, spawn_radius }, .{ spawn_radius, height - spawn_radius - 1 }, .{ width - spawn_radius - 1, height - spawn_radius - 1 } }
        else
            [_][2]usize{ .{ spawn_radius, spawn_radius }, .{ width - spawn_radius - 1, height - spawn_radius - 1 }, .{ 0, 0 }, .{ 0, 0 } };

        const active_spawns: usize = if (num_players == 4) 4 else 2;

        for (0..active_spawns) |i| {
            const spawn_x = spawn_points[i][0];
            const spawn_y = spawn_points[i][1];

            for (0..height) |y| {
                for (0..width) |x| {
                    const dx = @as(i32, @intCast(x)) - @as(i32, @intCast(spawn_x));
                    const dy = @as(i32, @intCast(y)) - @as(i32, @intCast(spawn_y));
                    const dist_sq = dx * dx + dy * dy;

                    if (dist_sq < @as(i32, @intCast(spawn_radius * spawn_radius))) {
                        if (dist_sq < @as(i32, @intCast((spawn_radius / 2) * (spawn_radius / 2)))) {
                            map[y][x].terrain = .grass;
                        }
                        else if (!map[y][x].terrain.isWalkable()) {
                            map[y][x].terrain = .grass;
                        }
                    }
                }
            }
        }
    }

    pub fn deinit(self: *MapGenerator, map: [][]terrain.Tile) void {
        for (map) |row| {
            self.allocator.free(row);
        }
        self.allocator.free(map);
    }
};
