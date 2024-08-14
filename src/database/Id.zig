site: Site,
id: u32,

pub fn fromUrl(url: []const u8) !Id {
    for (std.meta.tags(Site)) |site| {
        for (site.urls()) |site_url| {
            if (std.mem.startsWith(u8, url, site_url)) {
                const id = try std.fmt.parseUnsigned(u32, url[site_url.len..], 10);
                return Id{ .site = site, .id = id };
            }
        }
    }

    return error.InvalidUrl;
}

pub fn format(
    id: Id,
    comptime f: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = f;
    _ = options;
    return writer.print("{s}{d}", .{ id.site.url(), id.id });
}

pub const Site = enum(u8) {
    anidb,
    anilist,
    anisearch,
    kitsu,
    livechart,
    myanimelist,

    pub const all = std.meta.tags(Site);

    pub fn url(site: Site) []const u8 {
        return site.urls()[0];
    }

    /// The first url in the slice returned is the current url for that site. Anything after are
    /// old or alternative urls for the site.
    pub fn urls(site: Site) []const []const u8 {
        return switch (site) {
            .anidb => &.{
                "https://anidb.net/anime/",
            },
            .anilist => &.{
                "https://anilist.co/anime/",
            },
            .anisearch => &.{
                "https://anisearch.com/anime/",
            },
            .kitsu => &.{
                "https://kitsu.app/anime/",
                "https://kitsu.io/anime/",
            },
            .livechart => &.{
                "https://livechart.me/anime/",
            },
            .myanimelist => &.{
                "https://myanimelist.net/anime/",
            },
        };
    }
};

pub const Optional = enum(u32) {
    none = std.math.maxInt(u32),
    _,

    pub fn unwrap(id: Optional) ?u32 {
        if (id == .none)
            return null;
        return @intFromEnum(id);
    }
};

const Id = @This();

const std = @import("std");
