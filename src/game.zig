const std = @import("std");
const rl = @import("raylib");
const gui = @import("raygui");
const constants = @import("constants.zig");
const Camera = @import("camera.zig").Camera;
const InputState = @import("input.zig").InputState;
const Grid = @import("grid.zig").Grid;
const TileCoord = @import("grid.zig").TileCoord;
const VisibleBounds = @import("grid.zig").VisibleBounds;
const MapGenerator = @import("map_generator.zig").MapGenerator;
const empire_mod = @import("empire.zig");
const factory_mod = @import("factory.zig");
const resources = @import("resources.zig");

const Empire = empire_mod.Empire;
const EmpireManager = empire_mod.EmpireManager;
const FactoryManager = factory_mod.FactoryManager;
const FactoryDef = factory_mod.FactoryDef;
const FACTORY_TYPES = factory_mod.FACTORY_TYPES;
const ResourceBundle = resources.ResourceBundle;

pub const Game = struct {
    camera: Camera,
    input: InputState,
    grid: Grid,
    allocator: std.mem.Allocator,
    map_generator: MapGenerator,
    empires: EmpireManager,
    factories: FactoryManager,

    show_build_menu: bool = false,
    selected_factory_type: ?*const FactoryDef = null,

    last_time: i64,

    pub fn init(allocator: std.mem.Allocator) !Game {
        var map_gen = MapGenerator.init(allocator, @intCast(std.time.timestamp()));

        const map = try map_gen.generateSymmetric(
            constants.GRID_WIDTH,
            constants.GRID_HEIGHT,
            2,
        );

        var empires = EmpireManager.init(allocator);
        var factories = FactoryManager.init(allocator);

        const spawn_offset: i32 = 40;
        const player1 = try empires.addEmpire(
            "Player 1",
            empire_mod.EMPIRE_COLORS.BLUE,
            spawn_offset,
            spawn_offset,
        );
        player1.giveResources(empire_mod.STARTING_RESOURCES);

        const player2 = try empires.addEmpire(
            "Player 2",
            empire_mod.EMPIRE_COLORS.RED,
            @as(i32, @intCast(constants.GRID_WIDTH)) - spawn_offset,
            @as(i32, @intCast(constants.GRID_HEIGHT)) - spawn_offset,
        );
        player2.giveResources(empire_mod.STARTING_RESOURCES);

        _ = try factories.addFactory(&FACTORY_TYPES.SAWMILL, spawn_offset + 5, spawn_offset + 5, 0);

        return .{
            .camera = Camera.init(),
            .input = InputState.init(),
            .grid = Grid.init(allocator, map),
            .allocator = allocator,
            .map_generator = map_gen,
            .empires = empires,
            .factories = factories,
            .last_time = std.time.milliTimestamp(),
        };
    }

    pub fn deinit(self: *Game) void {
        self.factories.deinit();
        self.empires.deinit();
        self.map_generator.deinit(self.grid.map);
    }

    pub fn update(self: *Game) void {
        self.last_time = std.time.milliTimestamp();

        const mouse_position = rl.getMousePosition();
        const world_mouse_pos = self.camera.getWorldPosition(mouse_position);

        if (self.input.getPanDelta(mouse_position)) |delta| {
            self.camera.pan(delta);
        }

        const wheel = rl.getMouseWheelMove();
        self.camera.zoom(mouse_position, wheel);

        const hovered_tile = TileCoord.fromWorldPos(world_mouse_pos);

        if (rl.isKeyPressed(.b)) {
            self.show_build_menu = !self.show_build_menu;
            if (!self.show_build_menu) {
                self.selected_factory_type = null;
            }
        }

        if (rl.isKeyPressed(.escape)) {
            self.selected_factory_type = null;
            self.show_build_menu = false;
        }

        if (self.selected_factory_type) |factory_def| {
            if (rl.isMouseButtonPressed(.left) and hovered_tile.isValid()) {
                if (mouse_position.x > 250) {
                    self.tryPlaceFactory(factory_def, hovered_tile.x, hovered_tile.y);
                }
            }
        } else if (self.input.shouldSelectTile() and hovered_tile.isValid()) {
            if (mouse_position.x > 250 or !self.show_build_menu) {
                self.grid.selectTile(hovered_tile);
            }
        }

        self.updateFactories();
    }

    fn updateFactories(self: *Game) void {
        for (self.empires.empires.items) |*emp| {
            for (self.factories.factories.items) |*factory| {
                if (factory.owner_id == emp.id) {
                    factory.update(rl.getFrameTime(), &emp.resources);
                }
            }
        }
    }

    fn tryPlaceFactory(self: *Game, factory_def: *const FactoryDef, x: i32, y: i32) void {
        const player = self.empires.getLocalPlayer() orelse return;

        if (!player.canAfford(factory_def.build_cost)) {
            return;
        }

        if (!self.factories.canPlaceFactory(factory_def, x, y)) {
            return;
        }

        var valid_terrain = true;
        var fy: i32 = y;
        while (fy < y + @as(i32, factory_def.height)) : (fy += 1) {
            var fx: i32 = x;
            while (fx < x + @as(i32, factory_def.width)) : (fx += 1) {
                if (fx < 0 or fy < 0 or
                    fx >= @as(i32, @intCast(constants.GRID_WIDTH)) or
                    fy >= @as(i32, @intCast(constants.GRID_HEIGHT)))
                {
                    valid_terrain = false;
                    break;
                }
                const ux = @as(usize, @intCast(fx));
                const uy = @as(usize, @intCast(fy));
                if (!self.grid.map[uy][ux].terrain.isWalkable()) {
                    valid_terrain = false;
                    break;
                }
            }
            if (!valid_terrain) break;
        }

        if (!valid_terrain) return;

        if (player.spend(factory_def.build_cost)) {
            _ = self.factories.addFactory(factory_def, x, y, player.id) catch return;
        }
    }

    pub fn draw(self: *Game) void {
        rl.clearBackground(rl.Color.init(30, 30, 35, 255));

        self.camera.beginMode();

        const mouse_position = rl.getMousePosition();
        const world_mouse_pos = self.camera.getWorldPosition(mouse_position);
        const hovered_tile = TileCoord.fromWorldPos(world_mouse_pos);

        const bounds = self.camera.getVisibleBounds();
        const visible_bounds = VisibleBounds{
            .min_x = bounds.min_x,
            .min_y = bounds.min_y,
            .max_x = bounds.max_x,
            .max_y = bounds.max_y,
        };

        self.grid.draw(
            if (hovered_tile.isValid()) hovered_tile else null,
            visible_bounds,
        );

        self.factories.draw(bounds);

        if (self.selected_factory_type) |factory_def| {
            if (hovered_tile.isValid() and mouse_position.x > 250) {
                self.drawPlacementPreview(factory_def, hovered_tile.x, hovered_tile.y);
            }
        }

        self.camera.endMode();

        self.drawUI();
    }

    fn drawPlacementPreview(self: *Game, factory_def: *const FactoryDef, x: i32, y: i32) void {
        const tile_size = constants.TILE_SIZE;
        const px = x * tile_size;
        const py = y * tile_size;
        const w = @as(i32, factory_def.width) * tile_size;
        const h = @as(i32, factory_def.height) * tile_size;

        const can_place = self.factories.canPlaceFactory(factory_def, x, y);
        const player = self.empires.getLocalPlayer();
        const can_afford = if (player) |p| p.canAfford(factory_def.build_cost) else false;

        const color = if (can_place and can_afford)
            rl.Color.init(0, 255, 0, 100)
        else
            rl.Color.init(255, 0, 0, 100);

        rl.drawRectangle(px, py, w, h, color);
        rl.drawRectangleLines(px, py, w, h, rl.Color.init(255, 255, 255, 200));
    }

    fn drawUI(self: *Game) void {
        self.drawResourcePanel();

        if (self.show_build_menu) {
            self.drawBuildMenu();
        }

        const inst_y = constants.SCREEN_HEIGHT - 30;
        rl.drawText("B: Build Menu | ESC: Cancel | Right-click drag: Pan | Scroll: Zoom", 10, @intCast(inst_y), 16, rl.Color.init(200, 200, 200, 255));
    }

    fn drawResourcePanel(self: *Game) void {
        const player = self.empires.getLocalPlayer() orelse return;
        const res = player.resources;

        rl.drawRectangle(10, 10, 400, 40, rl.Color.init(0, 0, 0, 180));
        rl.drawRectangleLines(10, 10, 400, 40, player.color);

        var x_offset: i32 = 20;
        const y_pos: i32 = 20;

        // Coins
        rl.drawText("$", x_offset, y_pos, 20, rl.Color.init(255, 215, 0, 255));
        x_offset += 15;
        var buf: [32:0]u8 = undefined;
        _ = std.fmt.bufPrintZ(&buf, "{d:.0}", .{res.coins}) catch {};
        rl.drawText(&buf, x_offset, y_pos, 20, .white);
        x_offset += 70;

        // Gold
        rl.drawCircle(x_offset + 8, y_pos + 10, 8, rl.Color.init(255, 215, 0, 255));
        x_offset += 20;
        _ = std.fmt.bufPrintZ(&buf, "{d:.0}", .{res.gold}) catch {};
        rl.drawText(&buf, x_offset, y_pos, 20, .white);
        x_offset += 60;

        // Iron
        rl.drawCircle(x_offset + 8, y_pos + 10, 8, rl.Color.init(105, 105, 105, 255));
        x_offset += 20;
        _ = std.fmt.bufPrintZ(&buf, "{d:.0}", .{res.iron}) catch {};
        rl.drawText(&buf, x_offset, y_pos, 20, .white);
        x_offset += 60;

        // Wood
        rl.drawCircle(x_offset + 8, y_pos + 10, 8, rl.Color.init(139, 69, 19, 255));
        x_offset += 20;
        _ = std.fmt.bufPrintZ(&buf, "{d:.0}", .{res.wood}) catch {};
        rl.drawText(&buf, x_offset, y_pos, 20, .white);
        x_offset += 60;

        // Stone
        rl.drawCircle(x_offset + 8, y_pos + 10, 8, rl.Color.init(128, 128, 128, 255));
        x_offset += 20;
        _ = std.fmt.bufPrintZ(&buf, "{d:.0}", .{res.stone}) catch {};
        rl.drawText(&buf, x_offset, y_pos, 20, .white);
    }

    fn drawBuildMenu(self: *Game) void {
        const player = self.empires.getLocalPlayer() orelse return;

        const panel_x: i32 = 10;
        const panel_y: i32 = 60;
        const panel_w: i32 = 240;
        const item_h: i32 = 70;
        const padding: i32 = 5;

        const num_items = FACTORY_TYPES.ALL.len;
        const panel_h = @as(i32, @intCast(num_items)) * (item_h + padding) + padding + 25;

        rl.drawRectangle(panel_x, panel_y, panel_w, panel_h, rl.Color.init(20, 20, 25, 240));
        rl.drawRectangleLines(panel_x, panel_y, panel_w, panel_h, rl.Color.init(100, 100, 120, 255));

        rl.drawText("BUILD MENU", panel_x + 10, panel_y + 5, 16, .white);

        var buf: [32:0]u8 = undefined;

        var y: i32 = panel_y + 25;
        for (FACTORY_TYPES.ALL) |factory_def| {
            const can_afford = player.canAfford(factory_def.build_cost);
            const is_selected = if (self.selected_factory_type) |sel| sel == factory_def else false;

            const btn_x = panel_x + padding;
            const btn_w = panel_w - padding * 2;

            const bg_color = if (is_selected)
                rl.Color.init(60, 80, 120, 255)
            else if (can_afford)
                rl.Color.init(40, 40, 50, 255)
            else
                rl.Color.init(30, 30, 35, 255);

            rl.drawRectangle(btn_x, y, btn_w, item_h, bg_color);

            const border_color = if (is_selected)
                rl.Color.init(100, 150, 255, 255)
            else if (can_afford)
                rl.Color.init(80, 80, 100, 255)
            else
                rl.Color.init(50, 50, 60, 255);
            rl.drawRectangleLines(btn_x, y, btn_w, item_h, border_color);

            rl.drawRectangle(btn_x + 5, y + 5, 20, 20, factory_def.color);

            const name_color = if (can_afford) rl.Color.white else rl.Color.init(100, 100, 100, 255);
            rl.drawText(factory_def.name, btn_x + 30, y + 5, 16, name_color);

            _ = std.fmt.bufPrintZ(&buf, "{d}x{d}", .{ factory_def.width, factory_def.height }) catch {};
            rl.drawText(&buf, btn_x + 180, y + 5, 14, rl.Color.init(150, 150, 150, 255));

            var cost_x = btn_x + 5;
            const cost_y = y + 28;

            if (factory_def.build_cost.coins > 0) {
                rl.drawText("$", cost_x, cost_y, 12, rl.Color.init(255, 215, 0, 255));
                cost_x += 10;
                _ = std.fmt.bufPrintZ(&buf, "{d:.0}", .{factory_def.build_cost.coins}) catch {};
                rl.drawText(&buf, cost_x, cost_y, 12, rl.Color.init(200, 200, 200, 255));
                cost_x += 35;
            }
            if (factory_def.build_cost.wood > 0) {
                rl.drawCircle(cost_x + 5, cost_y + 6, 5, rl.Color.init(139, 69, 19, 255));
                cost_x += 12;
                _ = std.fmt.bufPrintZ(&buf, "{d:.0}", .{factory_def.build_cost.wood}) catch {};
                rl.drawText(&buf, cost_x, cost_y, 12, rl.Color.init(200, 200, 200, 255));
                cost_x += 35;
            }
            if (factory_def.build_cost.stone > 0) {
                rl.drawCircle(cost_x + 5, cost_y + 6, 5, rl.Color.init(128, 128, 128, 255));
                cost_x += 12;
                _ = std.fmt.bufPrintZ(&buf, "{d:.0}", .{factory_def.build_cost.stone}) catch {};
                rl.drawText(&buf, cost_x, cost_y, 12, rl.Color.init(200, 200, 200, 255));
                cost_x += 35;
            }
            if (factory_def.build_cost.iron > 0) {
                rl.drawCircle(cost_x + 5, cost_y + 6, 5, rl.Color.init(105, 105, 105, 255));
                cost_x += 12;
                _ = std.fmt.bufPrintZ(&buf, "{d:.0}", .{factory_def.build_cost.iron}) catch {};
                rl.drawText(&buf, cost_x, cost_y, 12, rl.Color.init(200, 200, 200, 255));
            }

            const prod_y = y + 48;
            var prod_x = btn_x + 5;

            for (factory_def.outputs) |output| {
                const res_color = switch (output.resource) {
                    .coins => rl.Color.init(255, 215, 0, 255),
                    .gold => rl.Color.init(255, 215, 0, 255),
                    .iron => rl.Color.init(105, 105, 105, 255),
                    .wood => rl.Color.init(139, 69, 19, 255),
                    .stone => rl.Color.init(128, 128, 128, 255),
                };
                rl.drawText("+", prod_x, prod_y, 12, rl.Color.init(100, 255, 100, 255));
                prod_x += 10;
                _ = std.fmt.bufPrintZ(&buf, "{d:.1}/s", .{output.per_second}) catch {};
                rl.drawText(&buf, prod_x, prod_y, 12, res_color);
                prod_x += 50;
            }

            for (factory_def.inputs) |input| {
                const res_color = switch (input.resource) {
                    .coins => rl.Color.init(255, 215, 0, 255),
                    .gold => rl.Color.init(255, 215, 0, 255),
                    .iron => rl.Color.init(105, 105, 105, 255),
                    .wood => rl.Color.init(139, 69, 19, 255),
                    .stone => rl.Color.init(128, 128, 128, 255),
                };
                rl.drawText("-", prod_x, prod_y, 12, rl.Color.init(255, 100, 100, 255));
                prod_x += 10;
                _ = std.fmt.bufPrintZ(&buf, "{d:.1}/s", .{input.per_second}) catch {};
                rl.drawText(&buf, prod_x, prod_y, 12, res_color);
                prod_x += 50;
            }

            const mouse = rl.getMousePosition();
            const mx = @as(i32, @intFromFloat(mouse.x));
            const my = @as(i32, @intFromFloat(mouse.y));

            if (mx >= btn_x and mx < btn_x + btn_w and my >= y and my < y + item_h) {
                if (rl.isMouseButtonPressed(.left) and can_afford) {
                    self.selected_factory_type = factory_def;
                }
            }

            y += item_h + padding;
        }
    }
};
