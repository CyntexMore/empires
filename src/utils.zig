const build_options = @import("build_options");

pub fn getResourcePath(comptime subpath: []const u8) [:0]const u8 {
    return build_options.resources_path ++ "/" ++ subpath;
}

