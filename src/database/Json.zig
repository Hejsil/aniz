//! The anime-offline-database schema converted to Zig code. Used for parsing the JSON database.
//! See https://github.com/manami-project/anime-offline-database/blob/master/anime-offline-database.schema.json

license: License,
repository: []const u8,
lastUpdate: []const u8,
data: []const Anime,

pub const License = struct {
    name: []const u8,
    url: []const u8,
};

pub const Anime = struct {
    sources: []const []const u8,
    title: []const u8,
    type: Type,
    episodes: u16,
    status: Status,
    animeSeason: SeasonAndYear,
    picture: []const u8,
    thumbnail: []const u8,
    synonyms: []const []const u8,
    relatedAnime: []const []const u8,
    tags: []const []const u8,
    duration: Duration = .{
        .value = 0,
        .unit = .SECONDS,
    },

    const SeasonAndYear = struct {
        season: Season,
        year: u16 = 0,
    };

    const Duration = struct {
        value: u16,
        unit: Unit,

        const Unit = enum {
            SECONDS,
        };
    };
};

pub const Type = enum {
    TV,
    MOVIE,
    OVA,
    ONA,
    SPECIAL,
    UNKNOWN,
};

pub const Status = enum {
    FINISHED,
    ONGOING,
    UPCOMING,
    UNKNOWN,
};

pub const Season = enum {
    SPRING,
    SUMMER,
    FALL,
    WINTER,
    UNDEFINED,
};
