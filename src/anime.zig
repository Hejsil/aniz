const datetime = @import("datetime");
const mecha = @import("mecha");
const std = @import("std");

const debug = std.debug;
const heap = std.heap;
const json = std.json;
const math = std.math;
const mem = std.mem;

pub const Season = enum(u4) {
    spring,
    summer,
    fall,
    winter,
    undef,
};

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

pub const Id = struct {
    site: Site,
    id: u32,

    pub fn fromUrl(url: []const u8) !Id {
        inline for (@typeInfo(Site).Enum.fields) |field| {
            const site = @field(Site, field.name);
            const site_url = site.url();
            if (mem.startsWith(u8, url, site_url)) {
                const id = try std.fmt.parseUnsigned(u32, url[site_url.len..], 10);
                return Id{ .site = site, .id = id };
            }
        }

        return error.InvalidUrl;
    }
};

const link_size = 159;
const str_size = 179;

pub const Info = struct {
    anidb: u32,
    anilist: u32,
    anisearch: u32,
    kitsu: u32,
    livechart: u32,
    myanimelist: u32,
    title: [str_size:0]u8,
    image: [str_size:0]u8,
    year: u16,
    episodes: u16,
    type: Type,
    season: Season,

    pub const Type = enum(u4) {
        tv,
        movie,
        ova,
        ona,
        special,
        unknown,
    };

    pub fn id(info: Info) Id {
        inline for (@typeInfo(Site).Enum.fields) |field| {
            if (@field(info, field.name) != math.maxInt(u32))
                return .{ .site = @field(Site, field.name), .id = @field(info, field.name) };
        }
        return .{ .site = Site.anidb, .id = info.anidb };
    }

    fn getId(site: Site, urls: []const []const u8) u32 {
        for (urls) |url| {
            const res = Id.fromUrl(url) catch continue;
            if (res.site == site)
                return res.id;
        }

        return math.maxInt(u32);
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
            try res.append(allocator, try fromJson(stream));
        }

        try expectJsonToken(stream, .ObjectEnd);
        return res;
    }

    pub fn fromJson(stream: *json.TokenStream) !Info {
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

        if (entry.sources.len == 0)
            return error.InvalidEntry;

        const toBuf = sliceToZBuf(u8, str_size, 0);
        return Info{
            .anidb = getId(.anidb, entry.sources),
            .anilist = getId(.anilist, entry.sources),
            .anisearch = getId(.anisearch, entry.sources),
            .kitsu = getId(.kitsu, entry.sources),
            .livechart = getId(.livechart, entry.sources),
            .myanimelist = getId(.myanimelist, entry.sources),
            .title = toBuf(fba.allocator(), entry.title) catch return error.InvalidEntry,
            .image = toBuf(fba.allocator(), entry.picture) catch return error.InvalidEntry,
            .type = switch (entry.type) {
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
    }
};

pub const List = struct {
    entries: std.ArrayListUnmanaged(Entry),

    // Omg, stop making the deinit function take a mutable pointer plz...
    pub fn deinit(list: *List, allocator: mem.Allocator) void {
        list.entries.deinit(allocator);
    }

    pub fn fromDsv(allocator: mem.Allocator, dsv: []const u8) !List {
        var res = std.ArrayListUnmanaged(Entry){};
        errdefer res.deinit(allocator);

        var it = mem.tokenize(u8, dsv, "\n");
        while (it.next()) |line|
            try res.append(allocator, try Entry.fromDsv(line));
        return List{ .entries = res };
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

    pub fn find(list: List, ctx: anytype, match: fn (@TypeOf(ctx), Entry) bool) ?*Entry {
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
    title: [str_size:0]u8,
    id: Id,

    pub const Status = enum {
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
        switch (mem.order(u8, &a.title, &b.title)) {
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

    pub fn fromDsv(row: []const u8) !Entry {
        var fba = heap.FixedBufferAllocator.init("");
        return (dsv(fba.allocator(), row) catch return error.InvalidEntry).value;
    }

    pub fn writeToDsv(entry: Entry, writer: anytype) !void {
        try writer.print("{d:4>2}-{d:0>2}-{d:0>2}\t{s}\t{}\t{}\t{s}\t{s}{d}", .{
            entry.date.year,
            entry.date.month,
            entry.date.day,
            entry.status.toString(),
            entry.episodes,
            entry.watched,
            mem.sliceTo(&entry.title, 0),
            entry.id.site.url(),
            entry.id.id,
        });
    }

    const dsv = mecha.map(Entry, mecha.toStruct(Entry), mecha.combine(.{
        date,
        mecha.ascii.char('\t'),
        status,
        mecha.ascii.char('\t'),
        mecha.int(usize, .{ .parse_sign = false }),
        mecha.ascii.char('\t'),
        mecha.int(usize, .{ .parse_sign = false }),
        mecha.ascii.char('\t'),
        string,
        mecha.ascii.char('\t'),
        link,
        mecha.eos,
    }));

    const date = mecha.map(datetime.Date, mecha.toStruct(datetime.Date), mecha.combine(.{
        mecha.int(u16, .{ .parse_sign = false }),
        mecha.ascii.char('-'),
        mecha.int(u4, .{ .parse_sign = false }),
        mecha.ascii.char('-'),
        mecha.int(u8, .{ .parse_sign = false }),
    }));

    const status = mecha.convert(Status, Status.fromString, any);

    const string = mecha.convert([str_size:0]u8, sliceToZBuf(u8, str_size, 0), any);
    const link = mecha.convert(Id, struct {
        fn conv(_: mem.Allocator, in: []const u8) !Id {
            return Id.fromUrl(in);
        }
    }.conv, any);

    const any = mecha.many(mecha.ascii.not(mecha.ascii.char('\t')), .{ .collect = false });
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

fn expectJsonString(stream: *json.TokenStream, string: []const u8) !void {
    const token = switch ((try stream.next()) orelse return error.UnexpectEndOfStream) {
        .String => |string_token| string_token,
        else => return error.UnexpectJsonToken,
    };

    if (!mem.eql(u8, string, token.slice(stream.slice, stream.i - 1)))
        return error.UnexpectJsonString;
}

fn sliceToZBuf(
    comptime T: type,
    comptime len: usize,
    comptime sentinel: T,
) fn (mem.Allocator, []const T) mecha.Error![len:sentinel]T {
    return struct {
        fn func(_: mem.Allocator, slice: []const T) mecha.Error![len:sentinel]T {
            if (slice.len > len)
                return error.ParserFailed;

            var res: [len:sentinel]T = [_:sentinel]T{sentinel} ** len;
            mem.copy(T, &res, slice);
            return res;
        }
    }.func;
}
