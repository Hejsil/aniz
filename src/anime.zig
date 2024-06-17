const datetime = @import("datetime");
const mecha = @import("mecha");
const std = @import("std");

const debug = std.debug;
const fmt = std.fmt;
const heap = std.heap;
const json = std.json;
const math = std.math;
const mem = std.mem;

pub const Id = struct {
    site: Site,
    id: u32,

    pub fn fromUrl(url: []const u8) !Id {
        for (std.meta.tags(Site)) |site| {
            const site_url = site.url();
            if (mem.startsWith(u8, url, site_url)) {
                const id = try std.fmt.parseUnsigned(u32, url[site_url.len..], 10);
                return Id{ .site = site, .id = id };
            }
        }

        return error.InvalidUrl;
    }

    pub fn format(
        id: Id,
        comptime f: []const u8,
        options: fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = f;
        _ = options;
        return writer.print("{s}{d}", .{ id.site.url(), id.id });
    }

    pub const Site = enum(u3) {
        anidb,
        anilist,
        anisearch,
        kitsu,
        livechart,
        myanimelist,

        pub fn url(site: Site) []const u8 {
            return switch (site) {
                .anidb => "https://anidb.net/anime/",
                .anilist => "https://anilist.co/anime/",
                .anisearch => "https://anisearch.com/anime/",
                .kitsu => "https://kitsu.io/anime/",
                .livechart => "https://livechart.me/anime/",
                .myanimelist => "https://myanimelist.net/anime/",
            };
        }
    };
};

pub const Image = struct {
    base: Base,
    path: []const u8,

    pub fn format(
        image: Image,
        comptime f: []const u8,
        options: fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = f;
        _ = options;
        return writer.print("{s}{s}", .{ image.base.url(), image.path });
    }

    pub const Base = enum(u4) {
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
        notifymoe,

        pub fn fromUrl(str: []const u8) !Image.Base {
            inline for (@typeInfo(Image.Base).Enum.fields) |field| {
                const base = @field(Image.Base, field.name);
                const base_url = base.url();
                if (mem.startsWith(u8, str, base_url))
                    return base;
            }

            return error.InvalidUrl;
        }

        pub fn url(base: Image.Base) []const u8 {
            return switch (base) {
                .no_pic1 => "https://raw.githubusercontent.com/manami-project/anime-offline-database/master/pics/no_pic.png",
                .no_pic2 => "https://github.com/manami-project/anime-offline-database/raw/master/pics/no_pic.png",
                .livechart => "https://u.livechart.me/anime/",
                .anilist => "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/",
                .notifymoe => "https://media.notify.moe/images/anime/large/",
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
            };
        }
    };
};

pub const OptionalId = enum(u32) {
    none = math.maxInt(u32),
    _,

    pub fn unwrap(id: OptionalId) ?u32 {
        if (id == .none)
            return null;
        return @intFromEnum(id);
    }
};

pub const Info = struct {
    anidb: OptionalId,
    anilist: OptionalId,
    anisearch: OptionalId,
    kitsu: OptionalId,
    livechart: OptionalId,
    myanimelist: OptionalId,
    title: []const u8,
    image_base: Image.Base,
    image_path: []const u8,
    year: u16,
    episodes: u16,
    kind: Kind,
    season: Season,

    pub const Season = enum(u3) {
        spring,
        summer,
        fall,
        winter,
        undef,
    };

    pub const Kind = enum(u3) {
        tv,
        movie,
        ova,
        ona,
        special,
        unknown,
    };

    pub fn id(info: Info) Id {
        return info.idChecked() orelse unreachable;
    }

    fn idChecked(info: Info) ?Id {
        inline for (@typeInfo(Id.Site).Enum.fields) |field| {
            if (@field(info, field.name).unwrap()) |res|
                return Id{ .site = @field(Id.Site, field.name), .id = res };
        }
        return null;
    }

    fn getId(site: Id.Site, urls: []const []const u8) OptionalId {
        for (urls) |url| {
            const res = Id.fromUrl(url) catch continue;
            if (res.site == site)
                return @enumFromInt(res.id);
        }

        return .none;
    }

    pub fn image(info: Info) Image {
        return .{ .base = info.image_base, .path = info.image_path };
    }

    pub fn writeToDsv(info: Info, writer: anytype) !void {
        const info_id = info.id();
        try writer.print("{s}\t{}\t{s}\t{}\t{s}\t{}\t{}", .{
            @tagName(info.kind),
            info.year,
            @tagName(info.season),
            info.episodes,
            info.title,
            info_id,
            info.image(),
        });
    }

    pub fn deinit(info: Info, allocator: mem.Allocator) void {
        allocator.free(info.title);
        allocator.free(info.image);
    }
};

pub const List = struct {
    arena: heap.ArenaAllocator,
    entries: std.ArrayListUnmanaged(Entry),

    pub fn deinit(list: *List) void {
        list.entries.deinit(list.arena.child_allocator);
        list.arena.deinit();
    }

    pub fn fromDsv(allocator: mem.Allocator, dsv: []const u8) !List {
        var arena = heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var res = std.ArrayListUnmanaged(Entry){};
        errdefer res.deinit(allocator);

        var it = mem.tokenizeScalar(u8, dsv, '\n');
        while (it.next()) |line|
            try res.append(allocator, try Entry.fromDsv(arena.allocator(), line));
        return List{ .arena = arena, .entries = res };
    }

    pub fn writeToDsv(list: List, writer: anytype) !void {
        list.sort();
        for (list.entries.items) |entry| {
            try entry.writeToDsv(writer);
            try writer.writeAll("\n");
        }
    }

    pub fn findWithId(list: List, id: Id) ?*Entry {
        const index = list.findIndexWithId(id) orelse return null;
        return &list.entries.items[index];
    }

    pub fn findIndexWithId(list: List, id: Id) ?usize {
        return list.findIndex(id, struct {
            fn match(i: Id, entry: Entry) bool {
                return entry.id.id == i.id and entry.id.site == i.site;
            }
        }.match);
    }

    pub fn findIndex(list: List, ctx: anytype, match: *const fn (@TypeOf(ctx), Entry) bool) ?usize {
        for (list.entries.items, 0..) |entry, i| {
            if (match(ctx, entry))
                return i;
        }

        return null;
    }

    pub fn sort(list: List) void {
        std.mem.sort(Entry, list.entries.items, {}, struct {
            fn lessThan(_: void, a: Entry, b: Entry) bool {
                // Sort from biggest datetime to smallest. Most people would expect that the
                // newest entry they've seen is then one that ends up at the top of their list
                return b.lessThan(a);
            }
        }.lessThan);
    }
};

pub const Entry = struct {
    date: datetime.Date,
    status: Status,
    episodes: usize,
    watched: usize,
    title: []const u8,
    id: Id,

    pub const Status = enum(u3) {
        complete,
        dropped,
        on_hold,
        plan_to_watch,
        watching,

        pub fn fromString(_: mem.Allocator, str: []const u8) !Status {
            const map = comptime std.StaticStringMap(Status).initComptime(.{
                .{ "c", .complete },
                .{ "d", .dropped },
                .{ "o", .on_hold },
                .{ "p", .plan_to_watch },
                .{ "w", .watching },
            });
            return map.get(str) orelse return error.ParserFailed;
        }

        pub fn toString(s: Status) []const u8 {
            return switch (s) {
                .complete => "c",
                .dropped => "d",
                .on_hold => "o",
                .plan_to_watch => "p",
                .watching => "w",
            };
        }
    };

    pub fn lessThan(a: Entry, b: Entry) bool {
        switch (a.date.cmp(b.date)) {
            .lt => return true,
            .gt => return false,
            .eq => {},
        }
        switch (math.order(@intFromEnum(a.status), @intFromEnum(b.status))) {
            .lt => return true,
            .gt => return false,
            .eq => {},
        }
        switch (math.order(a.episodes, b.episodes)) {
            .lt => return true,
            .gt => return false,
            .eq => {},
        }
        switch (math.order(a.watched, b.watched)) {
            .lt => return true,
            .gt => return false,
            .eq => {},
        }
        switch (mem.order(u8, a.title, b.title)) {
            .lt => return true,
            .gt => return false,
            .eq => {},
        }
        switch (math.order(@intFromEnum(a.id.site), @intFromEnum(b.id.site))) {
            .lt => return true,
            .gt => return false,
            .eq => {},
        }
        switch (math.order(a.id.id, b.id.id)) {
            .lt => return true,
            .gt => return false,
            .eq => {},
        }
        return false;
    }

    pub fn fromDsv(allocator: mem.Allocator, row: []const u8) !Entry {
        return (dsv.parse(allocator, row) catch return error.InvalidEntry).value;
    }

    pub fn writeToDsv(entry: Entry, writer: anytype) !void {
        try writer.print("{d:4>2}-{d:0>2}-{d:0>2}\t{s}\t{}\t{}\t{s}\t{s}{d}", .{
            entry.date.year,
            entry.date.month,
            entry.date.day,
            entry.status.toString(),
            entry.episodes,
            entry.watched,
            entry.title,
            entry.id.site.url(),
            entry.id.id,
        });
    }

    const any_token = mecha.ascii.not(mecha.ascii.char('\t')).many(.{ .collect = false });
    const minus_token = mecha.ascii.char('-').discard();
    const status_token = any_token.convert(Status.fromString);
    const string_token = mecha.ascii.not(tab_token).many(.{});
    const tab_token = mecha.ascii.char('\t').discard();
    const usize_token = mecha.int(usize, .{ .parse_sign = false });

    const dsv = mecha.combine(.{
        date,
        tab_token,
        status_token,
        tab_token,
        usize_token,
        tab_token,
        usize_token,
        tab_token,
        string_token,
        tab_token,
        link,
        mecha.eos,
    }).map(mecha.toStruct(Entry));

    const date = mecha.combine(.{
        mecha.int(u16, .{ .parse_sign = false }),
        minus_token,
        mecha.int(u4, .{ .parse_sign = false }),
        minus_token,
        mecha.int(u8, .{ .parse_sign = false }),
    }).map(mecha.toStruct(datetime.Date));

    const link = any_token.convert(struct {
        fn conv(_: mem.Allocator, in: []const u8) !Id {
            return Id.fromUrl(in);
        }
    }.conv);
};
