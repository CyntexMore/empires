const build_options = @import("build_options");

pub fn getResourcePath(comptime subpath: []const u8) []const u8 {
    return build_options.resource_path ++ "/" ++ subpath;
}

