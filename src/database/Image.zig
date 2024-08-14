//! Image urls in the anime-offline-database all follow a similar pattern. They all start with a
//! base url and then have a path that is unique to the image. To save on memory, we only store
//! the path of the image url and then an enum that represents the base url.

base: Base,
path: []const u8,

pub fn fromUrl(str: []const u8) !Image {
    const base = try Base.fromUrl(str);
    return Image{ .base = base, .path = str[base.url().len..] };
}

pub fn format(
    image: Image,
    comptime f: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = f;
    _ = options;
    return writer.print("{s}{s}", .{ image.base.url(), image.path });
}

pub const Base = enum(u8) {
    no_pic1,
    no_pic2,
    anidb,
    anilist,
    animeplanet1,
    animeplanet2,
    anisearch1,
    anisearch2,
    anisearch3,
    kitsu1,
    kitsu2,
    livechart,
    myanimelist1,
    myanimelist2,
    notifymoe1,
    notifymoe2,
    kitsu3,

    pub fn fromUrl(str: []const u8) !Image.Base {
        for (std.meta.tags(Image.Base)) |base| {
            const base_url = base.url();
            if (std.mem.startsWith(u8, str, base_url))
                return base;
        }

        return error.InvalidUrl;
    }

    pub fn url(base: Image.Base) []const u8 {
        return switch (base) {
            .no_pic1 => "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/pics/no_pic.png",
            .no_pic2 => "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/pics/no_pic_thumbnail.png",
            .livechart => "https://u.livechart.me/anime/",
            .anilist => "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/",
            .notifymoe1 => "https://media.notify.moe/images/anime/large/",
            .notifymoe2 => "https://media.notify.moe/images/anime/small/",
            .kitsu1 => "https://media.kitsu.io/anime/poster_images/",
            .kitsu2 => "https://media.kitsu.io/anime/",
            .myanimelist1 => "https://cdn.myanimelist.net/images/anime/",
            .myanimelist2 => "https://cdn.myanimelist.net/images/",
            .anisearch1 => "https://cdn.anisearch.com/images/anime/cover/full/",
            .anisearch2 => "https://cdn.anisearch.com/images/anime/cover/",
            .anisearch3 => "https://www.anisearch.com/images/anime/cover/",
            .animeplanet1 => "https://cdn.anime-planet.com/images/anime/default/",
            .animeplanet2 => "https://cdn.anime-planet.com/anime/primary/",
            .anidb => "https://cdn.anidb.net/images/main/",
            .kitsu3 => "https://media.kitsu.app/anime/",
        };
    }
};

const Image = @This();

const std = @import("std");
