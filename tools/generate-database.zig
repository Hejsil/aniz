const anime = @import("anime");
const std = @import("std");

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const io = std.io;
const json = std.json;
const math = std.math;
const process = std.process;

pub fn main() !void {
    var arena_state = heap.ArenaAllocator.init(heap.page_allocator);
    const arena = arena_state.allocator();

    const args = try process.argsAlloc(arena);
    const in = args[1];
    const out = args[2];

    const database_json = try fs.cwd().readFileAlloc(
        arena,
        in,
        math.maxInt(usize),
    );

    var tokens = json.TokenStream.init(database_json);
    const database = try json.parse(Database, &tokens, .{ .allocator = arena });

    const out_file = try fs.cwd().createFile(out, .{});
    defer out_file.close();

    var buffered_stdout = io.bufferedWriter(out_file.writer());
    const writer = buffered_stdout.writer();
    try writer.writeAll(
        \\const anime = @import("anime");
        \\const std = @import("std");
        \\
        \\pub const StringIndex = enum(u32) {
        \\    _,
        \\
        \\    pub fn toString(index: @This()) [:0]const u8 {
        \\        return std.mem.sliceTo(index.toStringZ(), 0);
        \\    }
        \\
        \\    pub fn toStringZ(index: @This()) [*:0]const u8 {
        \\        return strings[@enumToInt(index)..].ptr;
        \\    }
        \\};
        \\
        \\pub fn info(index: usize) anime.Info {
        \\    return .{
        \\        .anidb = anidb[index],
        \\        .anilist = anilist[index],
        \\        .anisearch = anisearch[index],
        \\        .kitsu = kitsu[index],
        \\        .livechart = livechart[index],
        \\        .myanimelist = myanimelist[index],
        \\        .title = title[index].toString(),
        \\        .image_base = image_base[index],
        \\        .image_path = image_path[index].toString(),
        \\        .year = year[index],
        \\        .episodes = episodes[index],
        \\        .kind = season_and_kind[index].kind,
        \\        .season = season_and_kind[index].season,
        \\    };
        \\}
        \\
        \\pub fn synonyms(index: usize) []const StringIndex {
        \\    return synonyms_flatten[synonym_indexs[index]..][0..synonym_lengths[index]];
        \\}
        \\
        \\pub fn findWithId(link_id: anime.Id) ?usize {
        \\    const slice_to_search = switch (link_id.site) {
        \\        .anidb => anidb,
        \\        .anilist => anilist,
        \\        .anisearch => anisearch,
        \\        .kitsu => kitsu,
        \\        .livechart => livechart,
        \\        .myanimelist => myanimelist,
        \\    };
        \\    for (slice_to_search, 0..) |id, i| {
        \\        if (link_id.id == @enumToInt(id))
        \\            return i;
        \\    }
        \\
        \\    return null;
        \\}
        \\
        \\pub const SeasonAndKind = packed struct {
        \\    kind: anime.Info.Kind,
        \\    season: anime.Info.Season,
        \\};
        \\
        \\
    );

    var database_entries = std.ArrayList(Entry).init(arena);
    try database_entries.ensureUnusedCapacity(database.data.len);

    // Create a list of only valid database entries
    for (database.data) |entry| {
        for (entry.sources) |source| {
            _ = anime.Id.fromUrl(source) catch continue;
            database_entries.appendAssumeCapacity(entry);
            break;
        }
    }

    inline for (@typeInfo(anime.Id.Site).Enum.fields) |field| {
        try writer.print(
            \\pub const {s} = [_]anime.OptionalId{{
            \\
        , .{field.name});

        for (database_entries.items) |entry| {
            for (entry.sources) |source| {
                const id = anime.Id.fromUrl(source) catch continue;
                if (id.site == @field(anime.Id.Site, field.name)) {
                    try writer.print("    @intToEnum(anime.OptionalId, {}),\n", .{id.id});
                    break;
                }
            } else {
                try writer.writeAll("    .none,\n");
            }
        }

        try writer.writeAll(
            \\};
            \\
            \\
        );
    }

    const StringFields = enum { title, image_path };

    var string_indexs = std.StringHashMap(usize).init(arena);
    var strings = std.ArrayList(u8).init(arena);
    for (std.meta.tags(StringFields)) |field| {
        try writer.print(
            \\pub const {s} = [_]StringIndex {{
            \\
        , .{@tagName(field)});

        for (database_entries.items) |database_entry| {
            const string = switch (field) {
                .title => database_entry.title,
                .image_path => blk: {
                    const image_base = try anime.Image.Base.fromUrl(database_entry.picture);
                    break :blk database_entry.picture[image_base.url().len..];
                },
            };
            const entry = try string_indexs.getOrPut(string);
            if (!entry.found_existing) {
                entry.value_ptr.* = strings.items.len;
                try strings.appendSlice(string);
                try strings.append(0);
            }

            try writer.print("    @intToEnum(StringIndex, {}),\n", .{entry.value_ptr.*});
        }

        try writer.writeAll(
            \\};
            \\
            \\
        );
    }

    // Store synonyms compactly. We have on flat array with all synonyms. Then we have two other
    // arrays. One for indexs into the flat array and one for lengths. If one wants to access
    // the synonyms of an entry they have to do:
    // `synonyms_flatten[synonym_indexs[entry]..][0..synonym_lengths[entry]]`
    //
    // This saves about 3MB of binary size last time i measured.
    var synonyms = std.ArrayList(struct { index: usize, len: usize }).init(arena);
    try synonyms.ensureUnusedCapacity(database_entries.items.len);

    try writer.writeAll(
        \\const synonyms_flatten = [_]StringIndex {
        \\
    );
    var index: usize = 0;
    for (database_entries.items) |database_entry| {
        synonyms.appendAssumeCapacity(.{ .index = index, .len = database_entry.synonyms.len });
        index += database_entry.synonyms.len;

        for (database_entry.synonyms) |string| {
            const entry = try string_indexs.getOrPut(string);
            if (!entry.found_existing) {
                entry.value_ptr.* = strings.items.len;
                try strings.appendSlice(string);
                try strings.append(0);
            }
            try writer.print("    @intToEnum(StringIndex, {}),\n", .{entry.value_ptr.*});
        }
    }
    try writer.writeAll(
        \\};
        \\
        \\
    );

    try writer.writeAll(
        \\const synonym_indexs = [_]u32 {
        \\
    );
    for (synonyms.items) |synonym|
        try writer.print("    {},\n", .{synonym.index});
    try writer.writeAll(
        \\};
        \\
        \\
    );
    try writer.writeAll(
        \\const synonym_lengths = [_]u8 {
        \\
    );
    for (synonyms.items) |synonym|
        try writer.print("    {},\n", .{synonym.len});
    try writer.writeAll(
        \\};
        \\
        \\
    );

    try writer.print(
        \\pub const strings = "{}";
        \\
        \\
    , .{std.zig.fmtEscapes(strings.items)});

    const IntFields = enum { year, episodes };
    for (std.meta.tags(IntFields)) |field| {
        try writer.print(
            \\pub const {s} = [_]u16{{
            \\
        , .{@tagName(field)});

        for (database_entries.items) |entry| {
            try writer.print("    {},\n", .{switch (field) {
                .year => entry.animeSeason.year orelse 0,
                .episodes => entry.episodes,
            }});
        }

        try writer.writeAll(
            \\};
            \\
            \\
        );
    }

    try writer.writeAll(
        \\pub const season_and_kind = [_]SeasonAndKind{
        \\
    );
    for (database_entries.items) |entry| {
        const kind: anime.Info.Kind = switch (entry.type) {
            .TV => .tv,
            .MOVIE => .movie,
            .OVA => .ova,
            .ONA => .ona,
            .SPECIAL => .special,
            .UNKNOWN => .unknown,
        };
        const season: anime.Info.Season = switch (entry.animeSeason.season) {
            .SPRING => .spring,
            .SUMMER => .summer,
            .FALL => .fall,
            .WINTER => .winter,
            .UNDEFINED => .undef,
        };
        try writer.print("    .{{ .kind = .{s}, .season = .{s} }},\n", .{
            @tagName(kind),
            @tagName(season),
        });
    }
    try writer.writeAll(
        \\};
        \\
        \\
    );

    try writer.writeAll(
        \\pub const image_base = [_]anime.Image.Base{
        \\
    );

    for (database_entries.items) |database_entry| {
        const image_base = try anime.Image.Base.fromUrl(database_entry.picture);
        try writer.print("    .{s},\n", .{@tagName(image_base)});
    }

    try writer.writeAll(
        \\};
        \\
        \\
    );

    try buffered_stdout.flush();
}

const Database = struct {
    license: struct {
        name: []const u8,
        url: []const u8,
    },
    repository: []const u8,
    lastUpdate: []const u8,
    data: []const Entry,
};

const Entry = struct {
    sources: []const []const u8,
    title: []const u8,
    type: Type,
    episodes: u16,
    status: Status,
    animeSeason: struct {
        season: Season,
        year: ?u16,
    },
    picture: []const u8,
    thumbnail: []const u8,
    synonyms: []const []const u8,
    relations: []const []const u8,
    tags: []const []const u8,
};

const Type = enum {
    TV,
    MOVIE,
    OVA,
    ONA,
    SPECIAL,
    UNKNOWN,
};

const Status = enum {
    FINISHED,
    ONGOING,
    UPCOMING,
    UNKNOWN,
};

const Season = enum {
    SPRING,
    SUMMER,
    FALL,
    WINTER,
    UNDEFINED,
};
