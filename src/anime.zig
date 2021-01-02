const datetime = @import("datetime");
const mecha = @import("mecha");
const std = @import("std");

const debug = std.debug;
const heap = std.heap;
const json = std.json;
const math = std.math;
const mem = std.mem;

pub const Season = enum {
    spring,
    summer,
    fall,
    winter,
    undef,
};

pub const Info = struct {
    type: Type,
    year: usize,
    season: Season,
    episodes: usize,
    title: [255:0]u8,
    link: [255:0]u8,
    image: [255:0]u8,

    pub const Type = enum {
        tv,
        movie,
        ova,
        ona,
        special,
    };

    pub fn fromJsonList(stream: *json.TokenStream, allocator: *mem.Allocator) ![]Info {
        try expectJsonToken(stream, .ObjectBegin);
        try expectJsonString(stream, "data");
        try expectJsonToken(stream, .ArrayBegin);

        var res = std.ArrayList(Info).init(allocator);
        errdefer res.deinit();

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
            try res.append(try fromJson(stream));
        }

        try expectJsonToken(stream, .ObjectEnd);
        return res.toOwnedSlice();
    }

    pub fn fromJson(stream: *json.TokenStream) !Info {
        var buf: [std.mem.page_size * 10]u8 = undefined;
        var fba = heap.FixedBufferAllocator.init(&buf);

        @setEvalBranchQuota(100000000);
        const entry = try json.parse(
            struct {
                sources: []const []const u8,
                title: []const u8,
                type: enum { TV, Movie, OVA, ONA, Special },
                episodes: usize,
                status: enum { FINISHED, CURRENTLY, UPCOMING, UNKNOWN },
                animeSeason: struct {
                    season: enum { SPRING, SUMMER, FALL, WINTER, UNDEFINED },
                    year: ?usize,
                },
                picture: []const u8,
                thumbnail: []const u8,
                synonyms: []const []const u8,
                relations: []const []const u8,
                tags: []const []const u8,
            },
            stream,
            .{ .allocator = &fba.allocator },
        );

        if (entry.sources.len == 0)
            return error.InvalidEntry;

        return Info{
            .type = switch (entry.type) {
                .TV => .tv,
                .Movie => .movie,
                .OVA => .ova,
                .ONA => .ona,
                .Special => .special,
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
            .title = sliceToZBuf(u8, 255, 0)(entry.title) orelse return error.InvalidEntry,
            .link = sliceToZBuf(u8, 255, 0)(entry.sources[0]) orelse return error.InvalidEntry,
            .image = sliceToZBuf(u8, 255, 0)(entry.picture) orelse return error.InvalidEntry,
        };
    }

    pub fn fromDsv(row: []const u8) !Entry {
        return (dsv(row) orelse return error.InvalidEntry).value;
    }

    pub fn writeToDsv(info: Info, writer: anytype) !void {
        try writer.print("{s}\t{}\t{s}\t{}\t{s}\t{s}\t{s}", .{
            @tagName(info.type),
            info.year,
            @tagName(info.season),
            info.episodes,
            mem.spanZ(&info.title),
            mem.spanZ(&info.link),
            mem.spanZ(&info.image),
        });
    }

    const dsv = mecha.map(Info, mecha.toStruct(Info), mecha.combine(.{
        mecha.convert(Type, mache.toEnum(Type), any),
        mecha.ascii.char('\t'),
        mecha.int(usize, 10),
        mecha.ascii.char('\t'),
        mecha.convert(Season, mache.toEnum(Season), any),
        mecha.ascii.char('\t'),
        mecha.int(usize, 10),
        mecha.ascii.char('\t'),
        string,
        mecha.ascii.char('\t'),
        string,
        mecha.ascii.char('\t'),
        string,
        mecha.eos,
    }));

    const string = mecha.convert([255:0]u8, sliceToZBuf(u8, 255, 0), any);

    const any = mecha.many(mecha.ascii.not(mecha.ascii.char('\t')));
};

pub const List = struct {
    entries: std.ArrayListUnmanaged(Entry),

    // Omg, stop making the deinit function take a mutable pointer plz...
    pub fn deinit(list: *List, allocator: *mem.Allocator) void {
        list.entries.deinit(allocator);
    }

    pub fn fromDsv(allocator: *mem.Allocator, dsv: []const u8) !List {
        var res = std.ArrayListUnmanaged(Entry){};
        errdefer res.deinit(allocator);

        var it = mem.tokenize(dsv, "\n");
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

    pub fn findWithLink(list: List, link: []const u8) ?*Entry {
        return list.find(link, struct {
            fn match(l: []const u8, entry: Entry) bool {
                return mem.eql(u8, l, mem.spanZ(&entry.link));
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

    pub fn remove(list: *List, entry: *const Entry) void {}

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
    title: [255:0]u8,
    link: [255:0]u8,

    pub const Status = enum {
        complete,
        dropped,
        on_hold,
        plan_to_watch,
        watching,

        pub fn fromString(str: []const u8) ?Status {
            return std.ComptimeStringMap(Status, .{
                .{ "c", .complete },
                .{ "d", .dropped },
                .{ "o", .on_hold },
                .{ "p", .plan_to_watch },
                .{ "w", .watching },
            }).get(str);
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
        switch (mem.order(u8, &a.link, &b.link)) {
            .lt => return true,
            .gt => return false,
            .eq => {},
        }
        return false;
    }

    pub fn fromDsv(row: []const u8) !Entry {
        return (dsv(row) orelse return error.InvalidEntry).value;
    }

    pub fn writeToDsv(entry: Entry, writer: anytype) !void {
        try writer.print("{d:4>2}-{d:0>2}-{d:0>2}\t{s}\t{}\t{}\t{s}\t{s}", .{
            entry.date.year,
            entry.date.month,
            entry.date.day,
            entry.status.toString(),
            entry.episodes,
            entry.watched,
            mem.spanZ(&entry.title),
            mem.spanZ(&entry.link),
        });
    }

    const dsv = mecha.map(Entry, mecha.toStruct(Entry), mecha.combine(.{
        date,
        mecha.ascii.char('\t'),
        status,
        mecha.ascii.char('\t'),
        mecha.int(usize, 10),
        mecha.ascii.char('\t'),
        mecha.int(usize, 10),
        mecha.ascii.char('\t'),
        string,
        mecha.ascii.char('\t'),
        string,
        mecha.eos,
    }));

    const date = mecha.map(datetime.Date, mecha.toStruct(datetime.Date), mecha.combine(.{
        mecha.int(u16, 10),
        mecha.ascii.char('-'),
        mecha.int(u4, 10),
        mecha.ascii.char('-'),
        mecha.int(u8, 10),
    }));

    const status = mecha.convert(Status, Status.fromString, any);

    const string = mecha.convert([255:0]u8, sliceToZBuf(u8, 255, 0), any);

    const any = mecha.many(mecha.ascii.not(mecha.ascii.char('\t')));
};

fn expectJsonToken(stream: *json.TokenStream, id: @TagType(json.Token)) !void {
    const token = (try stream.next()) orelse return error.UnexpectEndOfStream;
    if (token != id)
        return error.UnexpectJsonToken;
}

fn expectJsonString(stream: *json.TokenStream, string: []const u8) !void {
    const token = switch ((try stream.next()) orelse return error.UnexpectEndOfStream) {
        .String => |string_token| string_token,
        else => return error.UnexpectJsonToken,
    };

    // TODO: Man, I really wanted to use `json.encodesTo` but the Zig standard library
    //       said "No fun allowed" so I'll have to make do with `mem.eql` even though
    //       that is the wrong api for this task...
    if (!mem.eql(u8, string, token.slice(stream.slice, stream.i - 1)))
        return error.UnexpectJsonString;
}

fn sliceToZBuf(comptime T: type, comptime len: usize, comptime sentinel: T) fn ([]const T) ?[len:sentinel]T {
    return struct {
        fn func(slice: []const T) ?[len:sentinel]T {
            if (slice.len > len)
                return null;

            var res: [len:sentinel]T = [_:sentinel]T{sentinel} ** len;
            mem.copy(T, &res, slice);
            return res;
        }
    }.func;
}
