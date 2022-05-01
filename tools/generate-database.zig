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

    var stream = json.TokenStream.init(database_json);
    const database = try anime.Info.fromJsonList(&stream, arena);

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
        \\pub fn get(index: usize) anime.Info {
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
        \\pub fn findWithId(link_id: anime.Id) ?usize {
        \\    const slice_to_search = switch (link_id.site) {
        \\        .anidb => anidb,
        \\        .anilist => anilist,
        \\        .anisearch => anisearch,
        \\        .kitsu => kitsu,
        \\        .livechart => livechart,
        \\        .myanimelist => myanimelist,
        \\    };
        \\    for (slice_to_search) |id, i| {
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

    inline for (@typeInfo(anime.Id.Site).Enum.fields) |field| {
        try writer.print(
            \\pub const {s} = [_]anime.OptionalId{{
            \\
        , .{field.name});

        const slice = switch (@field(anime.Id.Site, field.name)) {
            .anidb => database.items(.anidb),
            .anilist => database.items(.anilist),
            .anisearch => database.items(.anisearch),
            .kitsu => database.items(.kitsu),
            .livechart => database.items(.livechart),
            .myanimelist => database.items(.myanimelist),
        };

        for (slice) |opt_id| {
            if (opt_id.unwrap()) |id| {
                try writer.print("    @intToEnum(anime.OptionalId, {}),\n", .{id});
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
    inline for ([_]StringFields{ .title, .image_path }) |field| {
        try writer.print(
            \\pub const {s} = [_]StringIndex{{
            \\
        , .{@tagName(field)});

        const slice = switch (field) {
            .title => database.items(.title),
            .image_path => database.items(.image_path),
        };

        for (slice) |string| {
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

    try writer.print(
        \\pub const strings = "{}";
        \\
        \\
    , .{std.zig.fmtEscapes(strings.items)});

    const IntFields = enum { year, episodes };
    inline for ([_]IntFields{ .year, .episodes }) |field| {
        try writer.print(
            \\pub const {s} = [_]u16{{
            \\
        , .{@tagName(field)});

        const slice = switch (field) {
            .year => database.items(.year),
            .episodes => database.items(.episodes),
        };

        for (slice) |int|
            try writer.print("    {},\n", .{int});

        try writer.writeAll(
            \\};
            \\
            \\
        );
    }

    {
        const kinds = database.items(.kind);
        const seasons = database.items(.season);
        try writer.writeAll(
            \\pub const season_and_kind = [_]SeasonAndKind{
            \\
        );
        for (kinds) |_, i| {
            try writer.print("    .{{ .kind = .{s}, .season = .{s} }},\n", .{
                @tagName(kinds[i]),
                @tagName(seasons[i]),
            });
        }
        try writer.writeAll(
            \\};
            \\
            \\
        );
    }

    {
        const image_bases = database.items(.image_base);
        try writer.writeAll(
            \\pub const image_base = [_]anime.ImageBase{
            \\
        );
        for (image_bases) |image_base|
            try writer.print("    .{s},\n", .{@tagName(image_base)});
        try writer.writeAll(
            \\};
            \\
            \\
        );
    }

    try buffered_stdout.flush();
}
