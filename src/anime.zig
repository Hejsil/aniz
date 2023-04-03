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
        anidb,
        anilist,
        animeplanet1,
        animeplanet2,
        anisearch1,
        anisearch2,
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
                .livechart => "https://u.livechart.me/anime/",
                .anilist => "https://s4.anilist.co/file/anilistcdn/media/anime/cover/medium/",
                .notifymoe => "https://media.notify.moe/images/anime/large/",
                .kitsu1 => "https://media.kitsu.io/anime/poster_images/",
                .kitsu2 => "https://media.kitsu.io/anime/",
                .myanimelist1 => "https://cdn.myanimelist.net/images/anime/",
                .myanimelist2 => "https://cdn.myanimelist.net/images/",
                .anisearch1 => "https://cdn.anisearch.com/images/anime/cover/full/",
                .anisearch2 => "https://www.anisearch.com/images/anime/cover/",
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
        return @enumToInt(id);
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
                return @intToEnum(OptionalId, res.id);
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

    pub fn fromJsonList(stream: *json.TokenStream, allocator: mem.Allocator) !std.MultiArrayList(Info) {
        try expectJsonToken(stream, .ObjectBegin);
        try skipToField(stream, "data");
        try expectJsonToken(stream, .ArrayBegin);

        var res = std.MultiArrayList(Info){};
        errdefer res.deinit(allocator);

        while (true) {
            const token = (try stream.next()) orelse return error.UnexpectEndOfStream;
            if (token == .ArrayEnd)
                break;

            // HACK: Put back token. This code is actually not correct. The reason
            //       the token field exists in TokenStream is for cases when the
            //       StreamingParser generates two tokens. If we hit that case, then
            //       we're trying to throw away a token here. Jees this api is not
            //       fun when you wonna do custom deserialization.
            debug.assert(stream.token == null);
            stream.token = token;

            const entry = fromJson(allocator, stream) catch |err| switch (err) {
                error.InvalidEntry => continue,
                else => |e| return e,
            };
            try res.append(allocator, entry);
        }

        try expectJsonToken(stream, .ObjectEnd);
        return res;
    }

    pub fn fromJson(allocator: mem.Allocator, stream: *json.TokenStream) !Info {
        var buf: [std.mem.page_size * 20]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&buf);

        @setEvalBranchQuota(100000000);
        const entry = try json.parse(
            struct {
                sources: []const []const u8,
                title: []const u8,
                type: enum { TV, MOVIE, OVA, ONA, SPECIAL, UNKNOWN },
                episodes: u16,
                status: []const u8,
                animeSeason: struct {
                    season: enum { SPRING, SUMMER, FALL, WINTER, UNDEFINED },
                    year: ?u16,
                },
                picture: []const u8,
                thumbnail: []const u8,
                synonyms: []const []const u8,
                relations: []const []const u8,
                tags: []const []const u8,
            },
            stream,
            .{ .allocator = fba.allocator(), .allow_trailing_data = true },
        );

        const image_base = try Image.Base.fromUrl(entry.picture);
        var info = Info{
            .anidb = getId(.anidb, entry.sources),
            .anilist = getId(.anilist, entry.sources),
            .anisearch = getId(.anisearch, entry.sources),
            .kitsu = getId(.kitsu, entry.sources),
            .livechart = getId(.livechart, entry.sources),
            .myanimelist = getId(.myanimelist, entry.sources),
            .title = undefined,
            .image_base = image_base,
            .image_path = undefined,
            .kind = switch (entry.type) {
                .TV => .tv,
                .MOVIE => .movie,
                .OVA => .ova,
                .ONA => .ona,
                .SPECIAL => .special,
                .UNKNOWN => .unknown,
            },
            .year = entry.animeSeason.year orelse 0,
            .season = switch (entry.animeSeason.season) {
                .SPRING => .spring,
                .SUMMER => .summer,
                .FALL => .fall,
                .WINTER => .winter,
                .UNDEFINED => .undef,
            },
            .episodes = entry.episodes,
        };

        if (info.idChecked() == null)
            return error.InvalidEntry;

        info.title = try allocator.dupe(u8, entry.title);
        errdefer allocator.free(info.title);
        info.image_path = try allocator.dupe(u8, entry.picture[image_base.url().len..]);
        errdefer allocator.free(info.image_path);

        return info;
    }

    pub fn deinit(info: Info, allocator: mem.Allocator) void {
        allocator.free(info.title);
        allocator.free(info.image);
    }
};

pub const List = struct {
    arena: heap.ArenaAllocator,
    entries: std.ArrayListUnmanaged(Entry),

    // Omg, stop making the deinit function take a mutable pointer plz...
    pub fn deinit(list: *List) void {
        list.entries.deinit(list.arena.child_allocator);
        list.arena.deinit();
    }

    pub fn fromDsv(allocator: mem.Allocator, dsv: []const u8) !List {
        var arena = heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();

        var res = std.ArrayListUnmanaged(Entry){};
        errdefer res.deinit(allocator);

        var it = mem.tokenize(u8, dsv, "\n");
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
        return list.find(id, struct {
            fn match(i: Id, entry: Entry) bool {
                return entry.id.id == i.id and entry.id.site == i.site;
            }
        }.match);
    }

    pub fn find(list: List, ctx: anytype, match: *const fn (@TypeOf(ctx), Entry) bool) ?*Entry {
        for (list.entries.items) |*entry| {
            if (match(ctx, entry.*))
                return entry;
        }

        return null;
    }

    pub fn sort(list: List) void {
        std.sort.sort(Entry, list.entries.items, {}, struct {
            fn lessThan(_: void, a: Entry, b: Entry) bool {
                return a.lessThan(b);
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
            return std.ComptimeStringMap(Status, .{
                .{ "c", .complete },
                .{ "d", .dropped },
                .{ "o", .on_hold },
                .{ "p", .plan_to_watch },
                .{ "w", .watching },
            }).get(str) orelse return error.ParserFailed;
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
        switch (math.order(@enumToInt(a.status), @enumToInt(b.status))) {
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
        switch (math.order(@enumToInt(a.id.site), @enumToInt(b.id.site))) {
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
        return (dsv(allocator, row) catch return error.InvalidEntry).value;
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

    const any_token = mecha.many(mecha.ascii.not(mecha.ascii.char('\t')), .{ .collect = false });
    const minus_token = mecha.discard(mecha.ascii.char('-'));
    const status_token = mecha.convert(Status.fromString, any_token);
    const string_token = mecha.many(mecha.ascii.not(tab_token), .{});
    const tab_token = mecha.discard(mecha.ascii.char('\t'));
    const usize_token = mecha.int(usize, .{ .parse_sign = false });

    const dsv = mecha.map(mecha.toStruct(Entry), mecha.combine(.{
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
    }));

    const date = mecha.map(mecha.toStruct(datetime.Date), mecha.combine(.{
        mecha.int(u16, .{ .parse_sign = false }),
        minus_token,
        mecha.int(u4, .{ .parse_sign = false }),
        minus_token,
        mecha.int(u8, .{ .parse_sign = false }),
    }));

    const link = mecha.convert(struct {
        fn conv(_: mem.Allocator, in: []const u8) !Id {
            return Id.fromUrl(in);
        }
    }.conv, any_token);
};

fn expectJsonToken(stream: *json.TokenStream, id: std.meta.Tag(json.Token)) !void {
    const token = (try stream.next()) orelse return error.UnexpectEndOfStream;
    if (token != id)
        return error.UnexpectJsonToken;
}

fn skipToField(stream: *json.TokenStream, field: []const u8) !void {
    var level: usize = 0;
    while (try stream.next()) |token| switch (token) {
        .ObjectBegin => level += 1,
        .ObjectEnd => level = try math.sub(usize, level, 1),
        .String => |string_token| if (level == 0) {
            // TODO: Man, I really wanted to use `json.encodesTo` but the Zig standard library
            //       said "No fun allowed" so I'll have to make do with `mem.eql` even though
            //       that is the wrong api for this task...
            if (mem.eql(u8, field, string_token.slice(stream.slice, stream.i - 1)))
                return;
        },
        else => {},
    };

    return error.EndOfStream;
}
