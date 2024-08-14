//! An efficient representation of the anime-offline-database. Can be serialized to and from JSON and binary. The
//! binary format is used to store the database locally to avoid parsing the JSON file every time the program is run.

license_name: StringIntern.Index,
license_url: StringIntern.Index,
repository: StringIntern.Index,
last_update: StringIntern.Index,

entries: []const Entry,
synonyms: []const StringIntern.Index,
tags: []const StringIntern.Index,
related_sites: []const Id.Site,
related_ids: []const u32,
strings: [:0]const u8,

pub const Entry = extern struct {
    ids: Ids,

    title: StringIntern.Index,
    picture_path: StringIntern.Index,
    thumbnail_path: StringIntern.Index,

    synonyms_span: Span,
    related_span: Span,
    tags_span: Span,

    year: u16,
    episodes: u16,

    picture_base: Image.Base,
    thumbnail_base: Image.Base,

    pack: packed struct(u8) {
        kind: Kind,
        season: Season,
        status: Status,
    },

    pub const Season = enum(u3) {
        spring = @intFromEnum(Json.Season.SPRING),
        summer = @intFromEnum(Json.Season.SUMMER),
        fall = @intFromEnum(Json.Season.FALL),
        winter = @intFromEnum(Json.Season.WINTER),
        undef = @intFromEnum(Json.Season.UNDEFINED),
    };

    pub const Kind = enum(u3) {
        tv = @intFromEnum(Json.Type.TV),
        movie = @intFromEnum(Json.Type.MOVIE),
        ova = @intFromEnum(Json.Type.OVA),
        ona = @intFromEnum(Json.Type.ONA),
        special = @intFromEnum(Json.Type.SPECIAL),
        unknown = @intFromEnum(Json.Type.UNKNOWN),
    };

    pub const Status = enum(u2) {
        finished = @intFromEnum(Json.Status.FINISHED),
        ongoing = @intFromEnum(Json.Status.ONGOING),
        upcoming = @intFromEnum(Json.Status.UPCOMING),
        unknown = @intFromEnum(Json.Status.UNKNOWN),
    };

    pub fn picture(entry: Entry, data: [:0]const u8) Image {
        return .{ .base = entry.picture_base, .path = entry.picture_path.slice(data) };
    }

    pub fn thumbnail(entry: Entry, data: [:0]const u8) Image {
        return .{ .base = entry.thumbnail_base, .path = entry.thumbnail_path.slice(data) };
    }

    pub fn synonyms(entry: Entry, database: Database) []const StringIntern.Index {
        return database.synonyms[entry.synonyms_span.index..][0..entry.synonyms_span.len];
    }

    pub fn tags(entry: Entry, database: Database) []const StringIntern.Index {
        return database.tags[entry.tags_span.index..][0..entry.tags_span.len];
    }

    pub fn related(entry: Entry, database: Database) struct { []const Id.Site, []const u32 } {
        return .{
            database.related_sites[entry.related_span.index..][0..entry.related_span.len],
            database.related_ids[entry.related_span.index..][0..entry.related_span.len],
        };
    }

    pub fn fuzzyScore(entry: Entry, database: Database, pattern: []const u8) usize {
        var score = fuzzyScoreString(pattern, entry.title.ptr(database.strings));
        for (entry.synonyms(database)) |synonym|
            score = @min(score, fuzzyScoreString(pattern, synonym.ptr(database.strings)));

        return score;
    }

    pub fn serializeToDsv(entry: Entry, strings: [:0]const u8, writer: anytype) !void {
        try writer.print("{s}\t{}\t{s}\t{}\t{s}\t{}\t{}", .{
            @tagName(entry.pack.kind),
            entry.year,
            @tagName(entry.pack.season),
            entry.episodes,
            entry.title.slice(strings),
            entry.ids.primary(),
            entry.picture(strings),
        });
    }
};

// Lower score is better
fn fuzzyScoreString(pattern: []const u8, str: [*:0]const u8) usize {
    var score: usize = 0;
    var last_match: usize = 0;
    var i: usize = 0;
    for (pattern) |c| {
        while (str[i] != 0) {
            defer i += 1;

            if (std.ascii.toLower(c) != std.ascii.toLower(str[i]))
                continue;

            score += @intFromBool(c != str[i]);
            score += i -| (last_match + 1);
            last_match = i;
            break;
        } else return std.math.maxInt(usize);
    }

    // Find length by going to end of string
    while (str[i] != 0) : (i += 1) {}

    const len = i;
    score += ((len - pattern.len) * 2) * @intFromBool(pattern.len != 0);
    return score;
}

test fuzzyScoreString {
    try std.testing.expectEqual(@as(usize, std.math.maxInt(usize)), fuzzyScoreString("abc", "ab"));
    try std.testing.expectEqual(@as(usize, 0), fuzzyScoreString("", "abc"));
    try std.testing.expectEqual(@as(usize, 0), fuzzyScoreString("abc", "abc"));
    try std.testing.expectEqual(@as(usize, 1), fuzzyScoreString("abc", "Abc"));
    try std.testing.expectEqual(@as(usize, 2), fuzzyScoreString("abc", "ABc"));
    try std.testing.expectEqual(@as(usize, 3), fuzzyScoreString("abc", "ABC"));
    try std.testing.expectEqual(@as(usize, 3), fuzzyScoreString("abc", "abdc"));
    try std.testing.expectEqual(@as(usize, 0), fuzzyScoreString("attack on titan", "attack on titan"));
    try std.testing.expectEqual(@as(usize, 3), fuzzyScoreString("attack on titan", "Attack On Titan"));
    try std.testing.expectEqual(@as(usize, 0), fuzzyScoreString("Clannad", "Clannad"));
    try std.testing.expectEqual(@as(usize, 125), fuzzyScoreString("Clannad", "BJ Special: Hyakumannen Chikyuu no Tabi Bander Book"));
}

pub const Ids = extern struct {
    anidb: Id.Optional = .none,
    anilist: Id.Optional = .none,
    anisearch: Id.Optional = .none,
    kitsu: Id.Optional = .none,
    livechart: Id.Optional = .none,
    myanimelist: Id.Optional = .none,

    pub fn primary(ids: Ids) Id {
        return ids.primaryChecked() orelse unreachable;
    }

    pub fn primaryChecked(ids: Ids) ?Id {
        for (ids.all()) |id| {
            if (id != null)
                return id;
        }
        return null;
    }

    pub fn set(ids: *Ids, id: Id) void {
        switch (id.site) {
            inline else => |site| @field(ids, @tagName(site)) = @enumFromInt(id.id),
        }
    }

    pub fn has(ids: Ids, id: Id) bool {
        const opt_id: Id.Optional = @enumFromInt(id.id);
        switch (id.site) {
            inline else => |site| return @field(ids, @tagName(site)) == opt_id,
        }
    }

    pub fn all(ids: Ids) [Id.Site.all.len]?Id {
        var res: [Id.Site.all.len]?Id = undefined;
        inline for (&res, Id.Site.all) |*ptr, site| {
            if (@field(ids, @tagName(site)).unwrap()) |id| {
                ptr.* = .{ .site = site, .id = id };
            } else {
                ptr.* = null;
            }
        }

        return res;
    }
};

pub fn deserializeFromJson(allocator: std.mem.Allocator, json: []const u8) !Database {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();

    const arena = arena_state.allocator();

    const parsed = try std.json.parseFromSlice(
        Json,
        arena,
        json,
        .{},
    );

    var database_entries = std.ArrayList(Json.Anime).init(arena);
    try database_entries.ensureUnusedCapacity(parsed.value.data.len);

    // Create a list of only valid database entries
    for (parsed.value.data) |entry| {
        for (entry.sources) |source| {
            _ = Id.fromUrl(source) catch continue;
            database_entries.appendAssumeCapacity(entry);
            break;
        }
    }

    var intern = try StringIntern.init(allocator);
    defer intern.deinit(allocator);

    // Many entries have the same tags, so we intern them aswell to save memory
    var tags_intern = StringsIntern{};
    defer tags_intern.deinit(allocator);

    var tags_tmp = std.ArrayList(StringIntern.Index).init(allocator);
    defer tags_tmp.deinit();

    var entries = std.ArrayList(Entry).init(allocator);
    errdefer entries.deinit();

    var synonyms = std.ArrayList(StringIntern.Index).init(allocator);
    errdefer synonyms.deinit();

    var related_sites = std.ArrayList(Id.Site).init(allocator);
    errdefer related_sites.deinit();

    var related_ids = std.ArrayList(u32).init(allocator);
    errdefer related_ids.deinit();

    const license_name = try intern.put(allocator, parsed.value.license.name);
    const license_url = try intern.put(allocator, parsed.value.license.url);
    const repository = try intern.put(allocator, parsed.value.repository);
    const last_update = try intern.put(allocator, parsed.value.lastUpdate);

    for (parsed.value.data) |entry| {
        var ids: Ids = .{};

        for (entry.sources) |source| {
            const id = Id.fromUrl(source) catch continue; // TODO: Error handling
            ids.set(id);
        }
        if (ids.primaryChecked() == null)
            continue; // TODO: Error handling

        const picture = try Image.fromUrl(entry.picture);
        const thumbnail = try Image.fromUrl(entry.thumbnail);
        const title = try intern.put(allocator, entry.title);
        const picture_path = try intern.put(allocator, picture.path);
        const thumbnail_path = try intern.put(allocator, thumbnail.path);

        const synonyms_index = std.math.cast(u32, synonyms.items.len) orelse return error.OutOfMemory;
        const synonyms_len = std.math.cast(u32, entry.synonyms.len) orelse return error.OutOfMemory;

        try synonyms.ensureUnusedCapacity(synonyms_len);
        for (entry.synonyms) |synonym| {
            const index = try intern.put(allocator, synonym);
            synonyms.appendAssumeCapacity(index);
        }

        try tags_tmp.ensureTotalCapacity(entry.tags.len);
        tags_tmp.shrinkRetainingCapacity(0);

        for (entry.tags) |tag| {
            const index = try intern.put(allocator, tag);
            tags_tmp.appendAssumeCapacity(index);
        }

        const tags_span = try tags_intern.put(allocator, tags_tmp.items);

        std.debug.assert(related_ids.items.len == related_sites.items.len);
        const related_index = std.math.cast(u32, related_ids.items.len) orelse return error.OutOfMemory;

        try related_sites.ensureUnusedCapacity(entry.relatedAnime.len);
        try related_ids.ensureUnusedCapacity(entry.relatedAnime.len);
        for (entry.relatedAnime) |related| {
            const id = Id.fromUrl(related) catch continue; // TODO: Error handling
            related_sites.appendAssumeCapacity(id.site);
            related_ids.appendAssumeCapacity(id.id);
        }

        const related_len = std.math.cast(u32, related_ids.items.len - related_index) orelse return error.OutOfMemory;

        try entries.append(.{
            .ids = ids,
            .title = title,
            .picture_path = picture_path,
            .thumbnail_path = thumbnail_path,
            .synonyms_span = .{ .index = synonyms_index, .len = synonyms_len },
            .related_span = .{ .index = related_index, .len = related_len },
            .tags_span = tags_span,
            .year = entry.animeSeason.year,
            .episodes = entry.episodes,
            .picture_base = picture.base,
            .thumbnail_base = thumbnail.base,
            .pack = .{
                .kind = @enumFromInt(@intFromEnum(entry.type)),
                .season = @enumFromInt(@intFromEnum(entry.animeSeason.season)),
                .status = @enumFromInt(@intFromEnum(entry.status)),
            },
        });
    }

    const entries_slice = try entries.toOwnedSlice();
    errdefer allocator.free(entries_slice);

    const synonyms_slice = try synonyms.toOwnedSlice();
    errdefer allocator.free(synonyms_slice);

    const tags_slice = try tags_intern.data.toOwnedSlice(allocator);
    errdefer allocator.free(tags_slice);

    const related_sites_slice = try related_sites.toOwnedSlice();
    errdefer allocator.free(related_sites_slice);

    const related_ids_slice = try related_ids.toOwnedSlice();
    errdefer allocator.free(related_ids_slice);

    const strings_slice = try intern.data.toOwnedSliceSentinel(allocator, 0);
    errdefer allocator.free(strings_slice);

    return Database{
        .license_name = license_name,
        .license_url = license_url,
        .repository = repository,
        .last_update = last_update,
        .entries = entries_slice,
        .synonyms = synonyms_slice,
        .tags = tags_slice,
        .related_sites = related_sites_slice,
        .related_ids = related_ids_slice,
        .strings = strings_slice,
    };
}

pub fn serializeToJson(database: Database, writer: anytype, options: std.json.StringifyOptions) !void {
    var buf: [std.mem.page_size]u8 = undefined;
    var out = std.json.writeStream(writer, options);

    try out.beginObject();

    try out.objectField("license");
    try out.write(.{
        .name = database.license_name.slice(database.strings),
        .url = database.license_url.slice(database.strings),
    });
    try out.objectField("repository");
    try out.write(database.repository.slice(database.strings));
    try out.objectField("lastUpdate");
    try out.write(database.last_update.slice(database.strings));

    try out.objectField("data");
    try out.beginArray();
    for (database.entries) |entry| {
        try out.beginObject();

        try out.objectField("sources");
        try out.beginArray();
        for (entry.ids.all()) |m_id| {
            if (m_id) |id|
                try out.write(try std.fmt.bufPrint(&buf, "{}", .{id}));
        }
        try out.endArray();

        try out.objectField("title");
        try out.write(entry.title.slice(database.strings));

        try out.objectField("type");
        try out.write(@as(Json.Type, @enumFromInt(@intFromEnum(entry.pack.kind))));

        try out.objectField("episodes");
        try out.write(entry.episodes);

        try out.objectField("status");
        try out.write(@as(Json.Status, @enumFromInt(@intFromEnum(entry.pack.status))));

        try out.objectField("animeSeason");
        try out.write(.{
            .season = @as(Json.Season, @enumFromInt(@intFromEnum(entry.pack.season))),
            .year = entry.year,
        });

        try out.objectField("picture");
        try out.write(try std.fmt.bufPrint(&buf, "{}", .{entry.picture(database.strings)}));

        try out.objectField("thumbnail");
        try out.write(try std.fmt.bufPrint(&buf, "{}", .{entry.thumbnail(database.strings)}));

        try out.objectField("synonyms");
        try out.beginArray();
        for (entry.synonyms(database)) |synonym|
            try out.write(synonym.slice(database.strings));
        try out.endArray();

        try out.objectField("relatedAnime");
        try out.beginArray();
        const related_sites, const related_ids = entry.related(database);
        for (related_sites, related_ids) |related_site, related_id| {
            const related = Id{ .site = related_site, .id = related_id };
            try out.write(try std.fmt.bufPrint(&buf, "{}", .{related}));
        }
        try out.endArray();

        try out.objectField("tags");
        try out.beginArray();
        for (entry.tags(database)) |tag|
            try out.write(tag.slice(database.strings));
        try out.endArray();

        try out.endObject();
    }
    try out.endArray();

    try out.endObject();
}

const binary_magic: [4]u8 = "ANIZ".*;
const binary_version: u16 = 1;

const BinaryHeader = extern struct {
    magic: [4]u8 = binary_magic,
    version: u32 = binary_version,
    license_name: StringIntern.Index,
    license_url: StringIntern.Index,
    repository: StringIntern.Index,
    last_update: StringIntern.Index,
    entries: u32,
    synonyms: u32,
    tags: u32,
    related_sites: u32,
    related_ids: u32,
    strings: u32,
};

pub fn deserializeFromBinary(allocator: std.mem.Allocator, reader: anytype) !Database {
    const header = try reader.readStruct(BinaryHeader);
    if (!std.mem.eql(u8, &header.magic, &binary_magic))
        return error.InvalidData;
    if (header.version != binary_version)
        return error.InvalidData;

    const entries = try allocator.alloc(Entry, header.entries);
    errdefer allocator.free(entries);

    const synonyms = try allocator.alloc(StringIntern.Index, header.synonyms);
    errdefer allocator.free(synonyms);

    const tags = try allocator.alloc(StringIntern.Index, header.tags);
    errdefer allocator.free(tags);

    const related_sites = try allocator.alloc(Id.Site, header.related_sites);
    errdefer allocator.free(related_sites);

    const related_ids = try allocator.alloc(u32, header.related_ids);
    errdefer allocator.free(related_ids);

    const strings = try allocator.alloc(u8, header.strings);
    errdefer allocator.free(strings);

    try reader.readNoEof(std.mem.sliceAsBytes(entries));
    try reader.readNoEof(std.mem.sliceAsBytes(synonyms));
    try reader.readNoEof(std.mem.sliceAsBytes(tags));
    try reader.readNoEof(std.mem.sliceAsBytes(related_sites));
    try reader.readNoEof(std.mem.sliceAsBytes(related_ids));
    try reader.readNoEof(strings);

    if (strings.len == 0)
        return error.InvalidData;
    if (strings[strings.len - 1] != 0)
        return error.InvalidData;

    return .{
        .license_name = header.license_name,
        .license_url = header.license_url,
        .repository = header.repository,
        .last_update = header.last_update,
        .entries = entries,
        .synonyms = synonyms,
        .tags = tags,
        .related_sites = related_sites,
        .related_ids = related_ids,
        .strings = strings[0 .. strings.len - 1 :0],
    };
}

pub fn serializeToBinary(database: Database, writer: anytype) !void {
    try writer.writeStruct(BinaryHeader{
        .license_name = database.license_name,
        .license_url = database.license_url,
        .repository = database.repository,
        .last_update = database.last_update,
        .entries = std.math.cast(u32, database.entries.len) orelse return error.OutOfMemory,
        .synonyms = std.math.cast(u32, database.synonyms.len) orelse return error.OutOfMemory,
        .tags = std.math.cast(u32, database.tags.len) orelse return error.OutOfMemory,
        .related_sites = std.math.cast(u32, database.related_sites.len) orelse return error.OutOfMemory,
        .related_ids = std.math.cast(u32, database.related_ids.len) orelse return error.OutOfMemory,
        .strings = std.math.cast(u32, database.strings.len + 1) orelse return error.OutOfMemory,
    });

    try writer.writeAll(std.mem.sliceAsBytes(database.entries));
    try writer.writeAll(std.mem.sliceAsBytes(database.synonyms));
    try writer.writeAll(std.mem.sliceAsBytes(database.tags));
    try writer.writeAll(std.mem.sliceAsBytes(database.related_sites));
    try writer.writeAll(std.mem.sliceAsBytes(database.related_ids));
    try writer.writeAll(database.strings[0 .. database.strings.len + 1]);
}

pub fn deinit(database: *Database, allocator: std.mem.Allocator) void {
    allocator.free(database.entries);
    allocator.free(database.synonyms);
    allocator.free(database.tags);
    allocator.free(database.related_sites);
    allocator.free(database.related_ids);
    allocator.free(database.strings);
}

pub fn findWithId(database: Database, id: Id) ?*const Entry {
    const converted_id: Id.Optional = @enumFromInt(id.id);
    switch (id.site) {
        inline else => |site| {
            for (database.entries) |*entry| {
                if (@field(entry.ids, @tagName(site)) == converted_id)
                    return entry;
            }

            return null;
        },
    }
}

pub fn entriesWithIds(database: Database, ids: []const Id, list: *std.ArrayList(Entry)) !void {
    try list.ensureTotalCapacity(ids);
    for (database.entries.items) |entry| {
        for (ids) |id| {
            if (entry.ids.has(id))
                try list.append(entry);
        }
    }
}

pub const FilterOptions = struct {
    /// If not null, entries will search using this string. The search is fuzzy and the results will be sorted
    /// based on how well they match the search string.
    search: ?[]const u8 = null,

    /// If not null, only entries with one of the ides in this list will be included.
    ids: ?[]const Id = null,

    /// The allocator used for temporary allocations. If null then `out.allocator` will be used.
    tmp_allocator: ?std.mem.Allocator = null,
};

pub fn filterEntries(database: Database, out: *std.ArrayList(Entry), opt: FilterOptions) !void {
    const tmp_allocator = opt.tmp_allocator orelse out.allocator;

    var scores = std.ArrayList(usize).init(tmp_allocator);
    defer scores.deinit();

    try out.ensureUnusedCapacity(database.entries.len);
    try scores.ensureUnusedCapacity(database.entries.len);
    for (database.entries) |entry| {
        if (opt.ids) |ids| {
            for (ids) |id| {
                if (entry.ids.has(id))
                    break;
            } else continue;
        }

        if (opt.search) |search| {
            const score = entry.fuzzyScore(database, search);
            if (score == std.math.maxInt(usize))
                continue;

            scores.appendAssumeCapacity(score);
        }

        out.appendAssumeCapacity(entry);
    }

    if (opt.search) |_| {
        std.mem.sortContext(0, out.items.len, ScoredSortContext{
            .entries = out.items,
            .scores = scores.items,
        });
    }
}

const ScoredSortContext = struct {
    entries: []Entry,
    scores: []usize,

    pub fn swap(ctx: ScoredSortContext, a_index: usize, b_index: usize) void {
        std.mem.swap(Entry, &ctx.entries[a_index], &ctx.entries[b_index]);
        std.mem.swap(usize, &ctx.scores[a_index], &ctx.scores[b_index]);
    }

    pub fn lessThan(ctx: ScoredSortContext, a_index: usize, b_index: usize) bool {
        return ctx.scores[a_index] < ctx.scores[b_index];
    }
};

fn testTransform(input: []const u8, expected_output: []const u8) !void {
    var database_from_json = try deserializeFromJson(std.testing.allocator, input);
    defer database_from_json.deinit(std.testing.allocator);

    var actual_output = std.ArrayList(u8).init(std.testing.allocator);
    defer actual_output.deinit();
    try database_from_json.serializeToJson(actual_output.writer(), .{ .whitespace = .indent_2 });

    try std.testing.expectEqualStrings(expected_output, actual_output.items);

    // After testing the JSON serialization, test the binary serialization
    var binary_serialized = std.ArrayList(u8).init(std.testing.allocator);
    defer binary_serialized.deinit();
    try database_from_json.serializeToBinary(binary_serialized.writer());

    var fbs = std.io.fixedBufferStream(binary_serialized.items);
    var database_from_binary = try deserializeFromBinary(std.testing.allocator, fbs.reader());
    defer database_from_binary.deinit(std.testing.allocator);

    actual_output.shrinkRetainingCapacity(0);
    try database_from_binary.serializeToJson(actual_output.writer(), .{ .whitespace = .indent_2 });
    try std.testing.expectEqualStrings(expected_output, actual_output.items);
}

fn testCanonical(input: []const u8) !void {
    return testTransform(input, input);
}

test "json" {
    try testCanonical(
        \\{
        \\  "license": {
        \\    "name": "",
        \\    "url": ""
        \\  },
        \\  "repository": "",
        \\  "lastUpdate": "",
        \\  "data": []
        \\}
    );
}

test "binary version should be updated" {
    const json =
        \\{
        \\  "license": {
        \\    "name": "test1",
        \\    "url": "test2"
        \\  },
        \\  "repository": "test3",
        \\  "lastUpdate": "test4",
        \\  "data": [
        \\    {
        \\      "sources": [
        \\        "https://anidb.net/anime/8069",
        \\        "https://anilist.co/anime/9756",
        \\        "https://anisearch.com/anime/6601",
        \\        "https://kitsu.app/anime/5853",
        \\        "https://livechart.me/anime/3246",
        \\        "https://myanimelist.net/anime/9756"
        \\      ],
        \\      "title": "Mahou Shoujo Madoka★Magica",
        \\      "type": "TV",
        \\      "episodes": 12,
        \\      "status": "FINISHED",
        \\      "animeSeason": {
        \\        "season": "WINTER",
        \\        "year": 2011
        \\      },
        \\      "picture": "https://cdn.myanimelist.net/images/anime/11/55225.jpg",
        \\      "thumbnail": "https://cdn.myanimelist.net/images/anime/11/55225t.jpg",
        \\      "synonyms": [
        \\        "Büyücü Kız Madoka Magica",
        \\        "Cô gái phép thuật Madoka",
        \\        "MSMM",
        \\        "Madoka",
        \\        "Madoka Magica",
        \\        "Magical Girl Madoka Magica",
        \\        "Magical Girl Madoka Magika",
        \\        "Mahou Shoujo Madoka Magica",
        \\        "Mahou Shoujo Madoka Magika",
        \\        "Mahou Shoujo Madoka☆Magica",
        \\        "Mahō Shōjo Madoka Magica",
        \\        "Meduka Meguca",
        \\        "PMMM",
        \\        "Puella Magi Madoka Magica",
        \\        "madokamagica",
        \\        "madomagi",
        \\        "pmagi",
        \\        "Μάντοκα, το Μαγικό Κορίτσι",
        \\        "Волшебница Мадока Магика",
        \\        "Девочка-волшебница Мадока Магика",
        \\        "Девочка-волшебница Мадока☆Волшебство",
        \\        "Дівчина-чарівниця Мадока Маґіка",
        \\        "Чарівниця Мадока Магіка",
        \\        "הנערה הקסומה מאדוקה מאגיקה",
        \\        "مادوكا ماجيكا",
        \\        "مدوکا مجیکا دختر جادویی",
        \\        "สาวน้อยเวทมนตร์ มาโดกะ",
        \\        "まどマギ",
        \\        "まほうしょうじょまどかまぎか",
        \\        "マドマギ",
        \\        "小圆",
        \\        "魔法少女まどか★マギカ",
        \\        "魔法少女まどか★マギカ PUELLA MAGI MADOKA MAGICA",
        \\        "魔法少女まどか☆マギカ",
        \\        "魔法少女小圆",
        \\        "魔法少女小圓",
        \\        "마법소녀 마도카 마기카"
        \\      ],
        \\      "relatedAnime": [
        \\        "https://anidb.net/anime/11793",
        \\        "https://anidb.net/anime/14360",
        \\        "https://anidb.net/anime/15472",
        \\        "https://anidb.net/anime/16278",
        \\        "https://anidb.net/anime/16404",
        \\        "https://anidb.net/anime/8778",
        \\        "https://anilist.co/anime/101090",
        \\        "https://anilist.co/anime/104051",
        \\        "https://anilist.co/anime/10519",
        \\        "https://anilist.co/anime/11977",
        \\        "https://anilist.co/anime/11979",
        \\        "https://anilist.co/anime/11981",
        \\        "https://anisearch.com/anime/13854",
        \\        "https://anisearch.com/anime/6993",
        \\        "https://anisearch.com/anime/7409",
        \\        "https://kitsu.app/anime/11573",
        \\        "https://kitsu.app/anime/13871",
        \\        "https://kitsu.app/anime/42016",
        \\        "https://kitsu.app/anime/48919",
        \\        "https://kitsu.app/anime/6218",
        \\        "https://kitsu.app/anime/6636",
        \\        "https://kitsu.app/anime/6637",
        \\        "https://kitsu.app/anime/6638",
        \\        "https://livechart.me/anime/10663",
        \\        "https://livechart.me/anime/1947",
        \\        "https://livechart.me/anime/3495",
        \\        "https://livechart.me/anime/4910",
        \\        "https://livechart.me/anime/74",
        \\        "https://livechart.me/anime/972",
        \\        "https://livechart.me/anime/973",
        \\        "https://livechart.me/anime/9862",
        \\        "https://myanimelist.net/anime/10519",
        \\        "https://myanimelist.net/anime/11977",
        \\        "https://myanimelist.net/anime/11979",
        \\        "https://myanimelist.net/anime/11981",
        \\        "https://myanimelist.net/anime/32153",
        \\        "https://myanimelist.net/anime/35300",
        \\        "https://myanimelist.net/anime/38256",
        \\        "https://myanimelist.net/anime/53932",
        \\        "https://myanimelist.net/anime/54209"
        \\      ],
        \\      "tags": [
        \\        "achronological order",
        \\        "action",
        \\        "aliens",
        \\        "alternate universe",
        \\        "angst",
        \\        "anthropomorphism",
        \\        "anti-hero",
        \\        "asia",
        \\        "award winning",
        \\        "coming of age",
        \\        "contemporary fantasy",
        \\        "cosmic horror",
        \\        "dark fantasy",
        \\        "drama",
        \\        "earth",
        \\        "ensemble cast",
        \\        "fantasy",
        \\        "female protagonist",
        \\        "gods",
        \\        "guns",
        \\        "henshin",
        \\        "horror",
        \\        "japan",
        \\        "lgbtq+ themes",
        \\        "love triangle",
        \\        "magic",
        \\        "magical girl",
        \\        "mahou shoujo",
        \\        "mature themes",
        \\        "melancholy",
        \\        "middle school",
        \\        "moe",
        \\        "monster",
        \\        "new",
        \\        "original work",
        \\        "philosophy",
        \\        "present",
        \\        "primarily child cast",
        \\        "primarily female cast",
        \\        "primarily teen cast",
        \\        "psychological",
        \\        "psychological drama",
        \\        "school",
        \\        "school life",
        \\        "spearplay",
        \\        "suicide",
        \\        "super power",
        \\        "supernatural drama",
        \\        "survival",
        \\        "suspense",
        \\        "swords & co",
        \\        "thriller",
        \\        "time loop",
        \\        "time manipulation",
        \\        "tomboy",
        \\        "tragedy",
        \\        "transfer students",
        \\        "twisted story",
        \\        "urban",
        \\        "urban fantasy",
        \\        "violence",
        \\        "witch"
        \\      ]
        \\    }
        \\  ]
        \\}
    ;

    try testCanonical(json);

    var database_from_json = try deserializeFromJson(std.testing.allocator, json);
    defer database_from_json.deinit(std.testing.allocator);

    var binary_serialized = std.ArrayList(u8).init(std.testing.allocator);
    defer binary_serialized.deinit();
    try database_from_json.serializeToBinary(binary_serialized.writer());

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(binary_serialized.items, &digest, .{});

    // If this test fails, then the binary version should be updated
    const expected_hash = "67ee3d157b8c899d33b533ae14ca71f4175d990d24a0e6b68d0e1883422fdac7";
    try std.testing.expectEqualStrings(expected_hash, &std.fmt.bytesToHex(digest, .lower));
}

test {
    _ = Json;
    _ = Id;
    _ = Image;
    _ = StringIntern;
    _ = StringsIntern;
}

const Database = @This();

const Span = StringsIntern.Span;

pub const Id = @import("database/Id.zig");
pub const Image = @import("database/Image.zig");

const Json = @import("database/Json.zig");
const StringIntern = @import("StringIntern.zig");
const StringsIntern = @import("StringsIntern.zig");

const builtin = @import("builtin");
const std = @import("std");
