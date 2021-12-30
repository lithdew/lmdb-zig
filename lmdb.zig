const std = @import("std");
const c = @cImport(@cInclude("lmdb.h"));

const os = std.os;
const fs = std.fs;
const mem = std.mem;
const math = std.math;
const meta = std.meta;
const debug = std.debug;
const testing = std.testing;

const panic = debug.panic;
const assert = debug.assert;

pub const Environment = packed struct {
    pub const Statistics = struct {
        page_size: usize,
        tree_height: usize,
        num_branch_pages: usize,
        num_leaf_pages: usize,
        num_overflow_pages: usize,
        num_entries: usize,
    };

    pub const Info = struct {
        map_address: ?[*]u8,
        map_size: usize,
        last_page_num: usize,
        last_tx_id: usize,
        max_num_reader_slots: usize,
        num_used_reader_slots: usize,
    };

    const Self = @This();

    inner: ?*c.MDB_env,

    pub const OpenFlags = struct {
        mode: c.mdb_mode_t = 0o664,
        map_size: ?usize = null,
        max_num_readers: ?usize = null,
        max_num_dbs: ?usize = null,

        fix_mapped_address: bool = false,
        no_sub_directory: bool = false,
        read_only: bool = false,
        use_writable_memory_map: bool = false,
        dont_sync_metadata: bool = false,
        dont_sync: bool = false,
        flush_asynchronously: bool = false,
        disable_thread_local_storage: bool = false,
        disable_locks: bool = false,
        disable_readahead: bool = false,
        disable_memory_initialization: bool = false,
        pub inline fn into(self: Self.OpenFlags) c_uint {
            var flags: c_uint = 0;
            if (self.fix_mapped_address) flags |= c.MDB_FIXEDMAP;
            if (self.no_sub_directory) flags |= c.MDB_NOSUBDIR;
            if (self.read_only) flags |= c.MDB_RDONLY;
            if (self.use_writable_memory_map) flags |= c.MDB_WRITEMAP;
            if (self.dont_sync_metadata) flags |= c.MDB_NOMETASYNC;
            if (self.dont_sync) flags |= c.MDB_NOSYNC;
            if (self.flush_asynchronously) flags |= c.MDB_MAPASYNC;
            if (self.disable_thread_local_storage) flags |= c.MDB_NOTLS;
            if (self.disable_locks) flags |= c.MDB_NOLOCK;
            if (self.disable_readahead) flags |= c.MDB_NORDAHEAD;
            if (self.disable_memory_initialization) flags |= c.MDB_NOMEMINIT;
            return flags;
        }
    };
    pub inline fn init(env_path: []const u8, flags: Self.OpenFlags) !Self {
        var inner: ?*c.MDB_env = null;

        try call(c.mdb_env_create, .{&inner});
        errdefer call(c.mdb_env_close, .{inner});

        if (flags.map_size) |map_size| {
            try call(c.mdb_env_set_mapsize, .{ inner, map_size });
        }
        if (flags.max_num_readers) |max_num_readers| {
            try call(c.mdb_env_set_maxreaders, .{ inner, @intCast(c_uint, max_num_readers) });
        }
        if (flags.max_num_dbs) |max_num_dbs| {
            try call(c.mdb_env_set_maxdbs, .{ inner, @intCast(c_uint, max_num_dbs) });
        }

        if (!mem.endsWith(u8, env_path, &[_]u8{0})) {
            assert(env_path.len + 1 <= fs.MAX_PATH_BYTES);

            var fixed_path: [fs.MAX_PATH_BYTES + 1]u8 = undefined;
            mem.copy(u8, &fixed_path, env_path);
            fixed_path[env_path.len] = 0;

            try call(c.mdb_env_open, .{ inner, fixed_path[0 .. env_path.len + 1].ptr, flags.into(), flags.mode });
        } else {
            try call(c.mdb_env_open, .{ inner, env_path.ptr, flags.into(), flags.mode });
        }

        return Self{ .inner = inner };
    }
    pub inline fn deinit(self: Self) void {
        call(c.mdb_env_close, .{self.inner});
    }

    pub const CopyFlags = packed struct {
        compact: bool = false,
        pub inline fn into(self: Self.CopyFlags) c_uint {
            var flags: c_uint = 0;
            if (self.compact) flags |= c.MDB_CP_COMPACT;
            return flags;
        }
    };
    pub inline fn copyTo(self: Self, backup_path: []const u8, flags: CopyFlags) !void {
        if (!mem.endsWith(u8, backup_path, &[_]u8{0})) {
            assert(backup_path.len + 1 <= fs.MAX_PATH_BYTES);

            var fixed_path: [fs.MAX_PATH_BYTES + 1]u8 = undefined;
            mem.copy(u8, &fixed_path, backup_path);
            fixed_path[backup_path.len] = 0;

            try call(c.mdb_env_copy2, .{ self.inner, fixed_path[0 .. backup_path.len + 1].ptr, flags.into() });
        } else {
            try call(c.mdb_env_copy2, .{ self.inner, backup_path.ptr, flags.into() });
        }
    }
    pub inline fn pipeTo(self: Self, fd_handle: os.fd_t, flags: CopyFlags) !void {
        try call(c.mdb_env_copyfd2, .{ self.inner, fd_handle, flags.into() });
    }
    pub inline fn getMaxKeySize(self: Self) usize {
        return @intCast(usize, c.mdb_env_get_maxkeysize(self.inner));
    }
    pub inline fn getMaxNumReaders(self: Self) usize {
        var max_num_readers: c_uint = 0;
        call(c.mdb_env_get_maxreaders, .{ self.inner, &max_num_readers }) catch |err| {
            panic("Environment.getMaxNumReaders(): {}", .{err});
        };
        return @intCast(usize, max_num_readers);
    }
    pub inline fn setMapSize(self: Self, map_size: ?usize) !void {
        try call(c.mdb_env_set_mapsize, .{ self.inner, if (map_size) |size| size else 0 });
    }

    pub const Flags = struct {
        fix_mapped_address: bool = false,
        no_sub_directory: bool = false,
        read_only: bool = false,
        use_writable_memory_map: bool = false,
        dont_sync_metadata: bool = false,
        dont_sync: bool = false,
        flush_asynchronously: bool = false,
        disable_thread_local_storage: bool = false,
        disable_locks: bool = false,
        disable_readahead: bool = false,
        disable_memory_initialization: bool = false,
        pub inline fn from(flags: c_uint) Flags {
            return Flags{
                .fix_mapped_address = flags & c.MDB_FIXEDMAP != 0,
                .no_sub_directory = flags & c.MDB_NOSUBDIR != 0,
                .read_only = flags & c.MDB_RDONLY != 0,
                .use_writable_memory_map = flags & c.MDB_WRITEMAP != 0,
                .dont_sync_metadata = flags & c.MDB_NOMETASYNC != 0,
                .dont_sync = flags & c.MDB_NOSYNC != 0,
                .flush_asynchronously = flags & c.MDB_MAPASYNC != 0,
                .disable_thread_local_storage = flags & c.MDB_NOTLS != 0,
                .disable_locks = flags & c.MDB_NOLOCK != 0,
                .disable_readahead = flags & c.MDB_NORDAHEAD != 0,
                .disable_memory_initialization = flags & c.MDB_NOMEMINIT != 0,
            };
        }
        pub inline fn into(self: Self.Flags) c_uint {
            var flags: c_uint = 0;
            if (self.fix_mapped_address) flags |= c.MDB_FIXEDMAP;
            if (self.no_sub_directory) flags |= c.MDB_NOSUBDIR;
            if (self.read_only) flags |= c.MDB_RDONLY;
            if (self.use_writable_memory_map) flags |= c.MDB_WRITEMAP;
            if (self.dont_sync_metadata) flags |= c.MDB_NOMETASYNC;
            if (self.dont_sync) flags |= c.MDB_NOSYNC;
            if (self.flush_asynchronously) flags |= c.MDB_MAPASYNC;
            if (self.disable_thread_local_storage) flags |= c.MDB_NOTLS;
            if (self.disable_locks) flags |= c.MDB_NOLOCK;
            if (self.disable_readahead) flags |= c.MDB_NORDAHEAD;
            if (self.disable_memory_initialization) flags |= c.MDB_NOMEMINIT;
            return flags;
        }
    };
    pub inline fn getFlags(self: Self) Flags {
        var inner: c_uint = undefined;
        call(c.mdb_env_get_flags, .{ self.inner, &inner }) catch |err| {
            panic("Environment.getFlags(): {}", .{err});
        };
        return Flags.from(inner);
    }

    pub const MutableFlags = struct {
        dont_sync_metadata: bool = false,
        dont_sync: bool = false,
        flush_asynchronously: bool = false,
        disable_memory_initialization: bool = false,
        pub inline fn into(self: Self.MutableFlags) c_uint {
            var flags: c_uint = 0;
            if (self.dont_sync_metadata) flags |= c.MDB_NOMETASYNC;
            if (self.dont_sync) flags |= c.MDB_NOSYNC;
            if (self.flush_asynchronously) flags |= c.MDB_MAPASYNC;
            if (self.disable_memory_initialization) flags |= c.MDB_NOMEMINIT;
            return flags;
        }
    };
    pub inline fn enableFlags(self: Self, flags: MutableFlags) void {
        call(c.mdb_env_set_flags, .{ self.inner, flags.into(), 1 }) catch |err| {
            panic("Environment.enableFlags(): {}", .{err});
        };
    }
    pub inline fn disableFlags(self: Self, flags: MutableFlags) void {
        call(c.mdb_env_set_flags, .{ self.inner, flags.into(), 0 }) catch |err| {
            panic("Environment.disableFlags(): {}", .{err});
        };
    }
    pub inline fn path(self: Self) []const u8 {
        var env_path: [:0]const u8 = undefined;
        call(c.mdb_env_get_path, .{ self.inner, @ptrCast([*c][*c]const u8, &env_path.ptr) }) catch |err| {
            panic("Environment.path(): {}", .{err});
        };
        env_path.len = mem.indexOfSentinel(u8, 0, env_path.ptr);
        return mem.span(env_path);
    }
    pub inline fn stat(self: Self) Statistics {
        var inner: c.MDB_stat = undefined;
        call(c.mdb_env_stat, .{ self.inner, &inner }) catch |err| {
            panic("Environment.stat(): {}", .{err});
        };
        return Statistics{
            .page_size = @intCast(usize, inner.ms_psize),
            .tree_height = @intCast(usize, inner.ms_depth),
            .num_branch_pages = @intCast(usize, inner.ms_branch_pages),
            .num_leaf_pages = @intCast(usize, inner.ms_leaf_pages),
            .num_overflow_pages = @intCast(usize, inner.ms_overflow_pages),
            .num_entries = @intCast(usize, inner.ms_entries),
        };
    }
    pub inline fn fd(self: Self) os.fd_t {
        var inner: os.fd_t = undefined;
        call(c.mdb_env_get_fd, .{ self.inner, &inner }) catch |err| {
            panic("Environment.fd(): {}", .{err});
        };
        return inner;
    }
    pub inline fn info(self: Self) Info {
        var inner: c.MDB_envinfo = undefined;
        call(c.mdb_env_info, .{ self.inner, &inner }) catch |err| {
            panic("Environment.info(): {}", .{err});
        };
        return Info{
            .map_address = @ptrCast(?[*]u8, inner.me_mapaddr),
            .map_size = @intCast(usize, inner.me_mapsize),
            .last_page_num = @intCast(usize, inner.me_last_pgno),
            .last_tx_id = @intCast(usize, inner.me_last_txnid),
            .max_num_reader_slots = @intCast(usize, inner.me_maxreaders),
            .num_used_reader_slots = @intCast(usize, inner.me_numreaders),
        };
    }
    pub inline fn begin(self: Self, flags: Transaction.Flags) !Transaction {
        var inner: ?*c.MDB_txn = null;
        const maybe_parent = if (flags.parent) |parent| parent.inner else null;
        try call(c.mdb_txn_begin, .{ self.inner, maybe_parent, flags.into(), &inner });
        return Transaction{ .inner = inner };
    }
    pub inline fn sync(self: Self, force: bool) !void {
        try call(c.mdb_env_sync, .{ self.inner, @as(c_int, if (force) 1 else 0) });
    }
    pub inline fn purge(self: Self) !usize {
        var count: c_int = undefined;
        try call(c.mdb_reader_check, .{ self.inner, &count });
        return @intCast(usize, count);
    }
};

pub const Database = struct {
    pub const OpenFlags = packed struct {
        compare_keys_in_reverse_order: bool = false,
        allow_duplicate_keys: bool = false,
        keys_are_integers: bool = false,
        duplicate_entries_are_fixed_size: bool = false,
        duplicate_keys_are_integers: bool = false,
        compare_duplicate_keys_in_reverse_order: bool = false,
        pub inline fn into(self: Self.OpenFlags) c_uint {
            var flags: c_uint = 0;
            if (self.compare_keys_in_reverse_order) flags |= c.MDB_REVERSEKEY;
            if (self.allow_duplicate_keys) flags |= c.MDB_DUPSORT;
            if (self.keys_are_integers) flags |= c.MDB_INTEGERKEY;
            if (self.duplicate_entries_are_fixed_size) flags |= c.MDB_DUPFIXED;
            if (self.duplicate_keys_are_integers) flags |= c.MDB_INTEGERDUP;
            if (self.compare_duplicate_keys_in_reverse_order) flags |= c.MDB_REVERSEDUP;
            return flags;
        }
    };

    pub const UseFlags = packed struct {
        compare_keys_in_reverse_order: bool = false,
        allow_duplicate_keys: bool = false,
        keys_are_integers: bool = false,
        duplicate_entries_are_fixed_size: bool = false,
        duplicate_keys_are_integers: bool = false,
        compare_duplicate_keys_in_reverse_order: bool = false,
        create_if_not_exists: bool = false,
        pub inline fn into(self: Self.UseFlags) c_uint {
            var flags: c_uint = 0;
            if (self.compare_keys_in_reverse_order) flags |= c.MDB_REVERSEKEY;
            if (self.allow_duplicate_keys) flags |= c.MDB_DUPSORT;
            if (self.keys_are_integers) flags |= c.MDB_INTEGERKEY;
            if (self.duplicate_entries_are_fixed_size) flags |= c.MDB_DUPFIXED;
            if (self.duplicate_keys_are_integers) flags |= c.MDB_INTEGERDUP;
            if (self.compare_duplicate_keys_in_reverse_order) flags |= c.MDB_REVERSEDUP;
            if (self.create_if_not_exists) flags |= c.MDB_CREATE;
            return flags;
        }
    };

    const Self = @This();

    inner: c.MDB_dbi,
    pub inline fn close(self: Self, env: Environment) void {
        call(c.mdb_dbi_close, .{ env.inner, self.inner });
    }
};

pub const Transaction = packed struct {
    pub const Flags = struct {
        parent: ?Self = null,
        read_only: bool = false,
        dont_sync: bool = false,
        dont_sync_metadata: bool = false,
        pub inline fn into(self: Self.Flags) c_uint {
            var flags: c_uint = 0;
            if (self.read_only) flags |= c.MDB_RDONLY;
            if (self.dont_sync) flags |= c.MDB_NOSYNC;
            if (self.dont_sync_metadata) flags |= c.MDB_NOMETASYNC;
            return flags;
        }
    };

    const Self = @This();

    inner: ?*c.MDB_txn,
    pub inline fn id(self: Self) usize {
        return @intCast(usize, c.mdb_txn_id(self.inner));
    }
    pub inline fn open(self: Self, flags: Database.OpenFlags) !Database {
        var inner: c.MDB_dbi = 0;
        try call(c.mdb_dbi_open, .{ self.inner, null, flags.into(), &inner });
        return Database{ .inner = inner };
    }
    pub inline fn use(self: Self, name: []const u8, flags: Database.UseFlags) !Database {
        var inner: c.MDB_dbi = 0;
        try call(c.mdb_dbi_open, .{ self.inner, name.ptr, flags.into(), &inner });
        return Database{ .inner = inner };
    }
    pub inline fn cursor(self: Self, db: Database) !Cursor {
        var inner: ?*c.MDB_cursor = undefined;
        try call(c.mdb_cursor_open, .{ self.inner, db.inner, &inner });
        return Cursor{ .inner = inner };
    }
    pub inline fn setKeyOrder(self: Self, db: Database, comptime order: fn (a: []const u8, b: []const u8) math.Order) !void {
        const S = struct {
            fn cmp(a: ?*const c.MDB_val, b: ?*const c.MDB_val) callconv(.C) c_int {
                const slice_a = @ptrCast([*]const u8, a.?.mv_data)[0..a.?.mv_size];
                const slice_b = @ptrCast([*]const u8, b.?.mv_data)[0..b.?.mv_size];
                return switch (order(slice_a, slice_b)) {
                    .eq => 0,
                    .lt => -1,
                    .gt => 1,
                };
            }
        };
        try call(c.mdb_set_compare, .{ self.inner, db.inner, S.cmp });
    }
    pub inline fn setItemOrder(self: Self, db: Database, comptime order: fn (a: []const u8, b: []const u8) math.Order) !void {
        const S = struct {
            fn cmp(a: ?*const c.MDB_val, b: ?*const c.MDB_val) callconv(.C) c_int {
                const slice_a = @ptrCast([*]const u8, a.?.mv_data)[0..a.?.mv_size];
                const slice_b = @ptrCast([*]const u8, b.?.mv_data)[0..b.?.mv_size];
                return switch (order(slice_a, slice_b)) {
                    .eq => 0,
                    .lt => -1,
                    .gt => 1,
                };
            }
        };
        try call(c.mdb_set_dupsort, .{ self.inner, db.inner, S.cmp });
    }
    pub inline fn get(self: Self, db: Database, key: []const u8) ![]const u8 {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v: c.MDB_val = undefined;
        try call(c.mdb_get, .{ self.inner, db.inner, k, &v });

        return @ptrCast([*]const u8, v.mv_data)[0..v.mv_size];
    }

    pub const PutFlags = packed struct {
        dont_overwrite_key: bool = false,
        dont_overwrite_item: bool = false,
        data_already_sorted: bool = false,
        set_already_sorted: bool = false,
        pub inline fn into(self: PutFlags) c_uint {
            var flags: c_uint = 0;
            if (self.dont_overwrite_key) flags |= c.MDB_NOOVERWRITE;
            if (self.dont_overwrite_item) flags |= c.MDB_NODUPDATA;
            if (self.data_already_sorted) flags |= c.MDB_APPEND;
            if (self.set_already_sorted) flags |= c.MDB_APPENDDUP;
            return flags;
        }
    };
    pub inline fn putItem(self: Self, db: Database, key: []const u8, val: anytype, flags: PutFlags) !void {
        const bytes = if (meta.trait.isIndexable(@TypeOf(val))) mem.span(val) else mem.asBytes(&val);
        return self.put(db, key, bytes, flags);
    }
    pub inline fn put(self: Self, db: Database, key: []const u8, val: []const u8, flags: PutFlags) !void {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v = &c.MDB_val{ .mv_size = val.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(val.ptr)) };
        try call(c.mdb_put, .{ self.inner, db.inner, k, v, flags.into() });
    }
    pub inline fn getOrPut(self: Self, db: Database, key: []const u8, val: []const u8) !?[]const u8 {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v = &c.MDB_val{ .mv_size = val.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(val.ptr)) };

        call(c.mdb_put, .{ self.inner, db.inner, k, v, c.MDB_NOOVERWRITE }) catch |err| switch (err) {
            error.AlreadyExists => return @ptrCast([*]u8, v.mv_data)[0..v.mv_size],
            else => return err,
        };

        return null;
    }

    pub const ReserveFlags = packed struct {
        dont_overwrite_key: bool = false,
        data_already_sorted: bool = false,
        pub inline fn into(self: ReserveFlags) c_uint {
            var flags: c_uint = c.MDB_RESERVE;
            if (self.dont_overwrite_key) flags |= c.MDB_NOOVERWRITE;
            if (self.data_already_sorted) flags |= c.MDB_APPEND;
            return flags;
        }
    };

    pub const ReserveResult = union(enum) {
        successful: []u8,
        found_existing: []const u8,
    };
    pub inline fn reserve(self: Self, db: Database, key: []const u8, val_len: usize, flags: ReserveFlags) !ReserveResult {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v = &c.MDB_val{ .mv_size = val_len, .mv_data = null };

        call(c.mdb_put, .{ self.inner, db.inner, k, v, flags.into() }) catch |err| switch (err) {
            error.AlreadyExists => return ReserveResult{
                .found_existing = @ptrCast([*]const u8, v.mv_data)[0..v.mv_size],
            },
            else => return err,
        };

        return ReserveResult{
            .successful = @ptrCast([*]u8, v.mv_data)[0..v.mv_size],
        };
    }
    pub inline fn del(self: Self, db: Database, key: []const u8, op: union(enum) { key: void, item: []const u8 }) !void {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v: ?*c.MDB_val = switch (op) {
            .key => null,
            .item => |item| &c.MDB_val{
                .mv_size = item.len,
                .mv_data = @intToPtr(?*anyopaque, @ptrToInt(item.ptr)),
            },
        };
        try call(c.mdb_del, .{ self.inner, db.inner, k, v });
    }
    pub inline fn drop(self: Self, db: Database, method: enum(c_int) { empty = 0, delete = 1 }) !void {
        try call(c.mdb_drop, .{ self.inner, db.inner, @enumToInt(method) });
    }
    pub inline fn deinit(self: Self) void {
        call(c.mdb_txn_abort, .{self.inner});
    }
    pub inline fn commit(self: Self) !void {
        try call(c.mdb_txn_commit, .{self.inner});
    }
    pub inline fn renew(self: Self) !void {
        try call(c.mdb_txn_renew, .{self.inner});
    }
    pub inline fn reset(self: Self) !void {
        try call(c.mdb_txn_reset, .{self.inner});
    }
};

pub const Cursor = packed struct {
    pub const Entry = struct {
        key: []const u8,
        val: []const u8,
    };

    pub fn Page(comptime T: type) type {
        return struct {
            key: []const u8,
            items: []align(1) const T,
        };
    }

    const Self = @This();

    inner: ?*c.MDB_cursor,
    pub inline fn deinit(self: Self) void {
        call(c.mdb_cursor_close, .{self.inner});
    }
    pub inline fn tx(self: Self) Transaction {
        return Transaction{ .inner = c.mdb_cursor_txn(self.inner) };
    }
    pub inline fn db(self: Self) Database {
        return Database{ .inner = c.mdb_cursor_dbi(self.inner) };
    }
    pub inline fn renew(self: Self, parent: Transaction) !void {
        try call(c.mdb_cursor_renew, .{ parent.inner, self.inner });
    }
    pub inline fn count(self: Self) usize {
        var inner: c.mdb_size_t = undefined;
        call(c.mdb_cursor_count, .{ self.inner, &inner }) catch |err| {
            panic("cursor is initialized, or database does not support duplicate keys: {}", .{err});
        };
        return @intCast(usize, inner);
    }

    pub fn updateItemInPlace(self: Self, current_key: []const u8, new_val: anytype) !void {
        const bytes = if (meta.trait.isIndexable(@TypeOf(new_val))) mem.span(new_val) else mem.asBytes(&new_val);
        return self.updateInPlace(current_key, bytes);
    }

    pub fn updateInPlace(self: Self, current_key: []const u8, new_val: []const u8) !void {
        var k = &c.MDB_val{ .mv_size = current_key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(current_key.ptr)) };
        var v = &c.MDB_val{ .mv_size = new_val.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(new_val.ptr)) };
        try call(c.mdb_cursor_put, .{ self.inner, k, v, c.MDB_CURRENT });
    }

    /// May not be used with databases supporting duplicate keys.
    pub fn reserveInPlace(self: Self, current_key: []const u8, new_val_len: usize) ![]u8 {
        var k = &c.MDB_val{ .mv_size = current_key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(current_key.ptr)) };
        var v = &c.MDB_val{ .mv_size = new_val_len, .mv_data = null };
        try call(c.mdb_cursor_put, .{ self.inner, k, v, c.MDB_CURRENT | c.MDB_RESERVE });
        return @ptrCast([*]u8, v.mv_data)[0..v.mv_size];
    }

    pub const PutFlags = packed struct {
        dont_overwrite_key: bool = false,
        dont_overwrite_item: bool = false,
        data_already_sorted: bool = false,
        set_already_sorted: bool = false,
        pub inline fn into(self: PutFlags) c_uint {
            var flags: c_uint = 0;
            if (self.dont_overwrite_key) flags |= c.MDB_NOOVERWRITE;
            if (self.dont_overwrite_item) flags |= c.MDB_NODUPDATA;
            if (self.data_already_sorted) flags |= c.MDB_APPEND;
            if (self.set_already_sorted) flags |= c.MDB_APPENDDUP;
            return flags;
        }
    };
    pub inline fn putItem(self: Self, key: []const u8, val: anytype, flags: PutFlags) !void {
        const bytes = if (meta.trait.isIndexable(@TypeOf(val))) mem.span(val) else mem.asBytes(&val);
        return self.put(key, bytes, flags);
    }
    pub inline fn put(self: Self, key: []const u8, val: []const u8, flags: PutFlags) !void {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v = &c.MDB_val{ .mv_size = val.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(val.ptr)) };
        try call(c.mdb_cursor_put, .{ self.inner, k, v, flags.into() });
    }
    pub inline fn putBatch(self: Self, key: []const u8, batch: anytype, flags: PutFlags) !usize {
        comptime assert(meta.trait.isIndexable(@TypeOf(batch)));

        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v = [_]c.MDB_val{
            .{ .mv_size = @sizeOf(meta.Elem(@TypeOf(batch))), .mv_data = @intToPtr(?*anyopaque, @ptrToInt(&batch[0])) },
            .{ .mv_size = mem.len(batch), .mv_data = undefined },
        };
        try call(c.mdb_cursor_put, .{ self.inner, k, &v, @intCast(c_uint, c.MDB_MULTIPLE) | flags.into() });

        return @intCast(usize, v[1].mv_size);
    }
    pub inline fn getOrPut(self: Self, key: []const u8, val: []const u8) !?[]const u8 {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v = &c.MDB_val{ .mv_size = val.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(val.ptr)) };

        call(c.mdb_cursor_put, .{ self.inner, k, v, c.MDB_NOOVERWRITE }) catch |err| switch (err) {
            error.AlreadyExists => return @ptrCast([*]u8, v.mv_data)[0..v.mv_size],
            else => return err,
        };

        return null;
    }

    pub const ReserveFlags = packed struct {
        dont_overwrite_key: bool = false,
        data_already_sorted: bool = false,
        pub inline fn into(self: ReserveFlags) c_uint {
            var flags: c_uint = c.MDB_RESERVE;
            if (self.dont_overwrite_key) flags |= c.MDB_NOOVERWRITE;
            if (self.data_already_sorted) flags |= c.MDB_APPEND;
            return flags;
        }
    };

    pub const ReserveResult = union(enum) {
        successful: []u8,
        found_existing: []const u8,
    };
    pub inline fn reserve(self: Self, key: []const u8, val_len: usize, flags: ReserveFlags) !ReserveResult {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v = &c.MDB_val{ .mv_size = val_len, .mv_data = null };

        call(c.mdb_cursor_put, .{ self.inner, k, v, flags.into() }) catch |err| switch (err) {
            error.AlreadyExists => return ReserveResult{
                .found_existing = @ptrCast([*]const u8, v.mv_data)[0..v.mv_size],
            },
            else => return err,
        };

        return ReserveResult{
            .successful = @ptrCast([*]u8, v.mv_data)[0..v.mv_size],
        };
    }
    pub inline fn del(self: Self, op: enum(c_uint) { key = c.MDB_NODUPDATA, item = 0 }) !void {
        call(c.mdb_cursor_del, .{ self.inner, @enumToInt(op) }) catch |err| switch (err) {
            error.InvalidParameter => return error.NotFound,
            else => return err,
        };
    }

    pub const Position = enum(c.MDB_cursor_op) {
        first = c.MDB_FIRST,
        first_item = c.MDB_FIRST_DUP,
        current = c.MDB_GET_CURRENT,
        last = c.MDB_LAST,
        last_item = c.MDB_LAST_DUP,
        next = c.MDB_NEXT,
        next_item = c.MDB_NEXT_DUP,
        next_key = c.MDB_NEXT_NODUP,
        prev = c.MDB_PREV,
        prev_item = c.MDB_PREV_DUP,
        prev_key = c.MDB_PREV_NODUP,
    };
    pub inline fn get(self: Self, pos: Position) !?Entry {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;
        call(c.mdb_cursor_get, .{ self.inner, &k, &v, @enumToInt(pos) }) catch |err| switch (err) {
            error.InvalidParameter => return if (pos == .current) null else err,
            error.NotFound => return null,
            else => return err,
        };
        return Entry{
            .key = @ptrCast([*]const u8, k.mv_data)[0..k.mv_size],
            .val = @ptrCast([*]const u8, v.mv_data)[0..v.mv_size],
        };
    }

    pub const PagePosition = enum(c.MDB_cursor_op) {
        current = c.MDB_GET_MULTIPLE,
        next = c.MDB_NEXT_MULTIPLE,
        prev = c.MDB_PREV_MULTIPLE,
    };
    pub inline fn getPage(self: Self, comptime T: type, pos: PagePosition) !?Page(T) {
        var k: c.MDB_val = undefined;
        var v: c.MDB_val = undefined;
        call(c.mdb_cursor_get, .{ self.inner, &k, &v, @enumToInt(pos) }) catch |err| switch (err) {
            error.NotFound => return null,
            else => return err,
        };
        return Page(T){
            .key = @ptrCast([*]const u8, k.mv_data)[0..k.mv_size],
            .items = mem.bytesAsSlice(T, @ptrCast([*]const u8, v.mv_data)[0..v.mv_size]),
        };
    }
    pub inline fn seekToItem(self: Self, key: []const u8, val: []const u8) !void {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v = &c.MDB_val{ .mv_size = val.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(val.ptr)) };
        try call(c.mdb_cursor_get, .{ self.inner, k, v, .MDB_GET_BOTH });
    }
    pub inline fn seekFromItem(self: Self, key: []const u8, val: []const u8) ![]const u8 {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v = &c.MDB_val{ .mv_size = val.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(val.ptr)) };
        try call(c.mdb_cursor_get, .{ self.inner, k, v, c.MDB_GET_BOTH_RANGE });
        return @ptrCast([*]const u8, v.mv_data)[0..v.mv_size];
    }
    pub inline fn seekTo(self: Self, key: []const u8) ![]const u8 {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v: c.MDB_val = undefined;
        try call(c.mdb_cursor_get, .{ self.inner, k, &v, c.MDB_SET_KEY });
        return @ptrCast([*]const u8, v.mv_data)[0..v.mv_size];
    }
    pub inline fn seekFrom(self: Self, key: []const u8) !Entry {
        var k = &c.MDB_val{ .mv_size = key.len, .mv_data = @intToPtr(?*anyopaque, @ptrToInt(key.ptr)) };
        var v: c.MDB_val = undefined;
        try call(c.mdb_cursor_get, .{ self.inner, k, &v, c.MDB_SET_RANGE });
        return Entry{
            .key = @ptrCast([*]const u8, k.mv_data)[0..k.mv_size],
            .val = @ptrCast([*]const u8, v.mv_data)[0..v.mv_size],
        };
    }
    pub inline fn first(self: Self) !?Entry {
        return self.get(.first);
    }
    pub inline fn firstItem(self: Self) !?Entry {
        return self.get(.first_item);
    }
    pub inline fn current(self: Self) !?Entry {
        return self.get(.current);
    }
    pub inline fn last(self: Self) !?Entry {
        return self.get(.last);
    }
    pub inline fn lastItem(self: Self) !?Entry {
        return self.get(.last_item);
    }
    pub inline fn next(self: Self) !?Entry {
        return self.get(.next);
    }
    pub inline fn nextItem(self: Self) !?Entry {
        return self.get(.next_item);
    }
    pub inline fn nextKey(self: Self) !?Entry {
        return self.get(.next_key);
    }
    pub inline fn prev(self: Self) !?Entry {
        return self.get(.prev);
    }
    pub inline fn prevItem(self: Self) !?Entry {
        return self.get(.prev_item);
    }
    pub inline fn prevKey(self: Self) !?Entry {
        return self.get(.prev_key);
    }
    pub inline fn currentPage(self: Self, comptime T: type) !?Page(T) {
        return self.getPage(T, .current);
    }
    pub inline fn nextPage(self: Self, comptime T: type) !?Page(T) {
        return self.getPage(T, .next);
    }
    pub inline fn prevPage(self: Self, comptime T: type) !?Page(T) {
        return self.getPage(T, .prev);
    }
};

inline fn ResultOf(comptime function: anytype) type {
    return if (@typeInfo(@TypeOf(function)).Fn.return_type == c_int) anyerror!void else void;
}

inline fn call(comptime function: anytype, args: anytype) ResultOf(function) {
    const rc = @call(.{}, function, args);
    if (ResultOf(function) == void) return rc;

    return switch (rc) {
        c.MDB_SUCCESS => {},
        c.MDB_KEYEXIST => error.AlreadyExists,
        c.MDB_NOTFOUND => error.NotFound,
        c.MDB_PAGE_NOTFOUND => error.PageNotFound,
        c.MDB_CORRUPTED => error.PageCorrupted,
        c.MDB_PANIC => error.Panic,
        c.MDB_VERSION_MISMATCH => error.VersionMismatch,
        c.MDB_INVALID => error.FileNotDatabase,
        c.MDB_MAP_FULL => error.MapSizeLimitReached,
        c.MDB_DBS_FULL => error.MaxNumDatabasesLimitReached,
        c.MDB_READERS_FULL => error.MaxNumReadersLimitReached,
        c.MDB_TLS_FULL => error.TooManyEnvironmentsOpen,
        c.MDB_TXN_FULL => error.TransactionTooBig,
        c.MDB_CURSOR_FULL => error.CursorStackLimitReached,
        c.MDB_PAGE_FULL => error.OutOfPageMemory,
        c.MDB_MAP_RESIZED => error.DatabaseExceedsMapSizeLimit,
        c.MDB_INCOMPATIBLE => error.IncompatibleOperation,
        c.MDB_BAD_RSLOT => error.InvalidReaderLocktableSlotReuse,
        c.MDB_BAD_TXN => error.TransactionNotAborted,
        c.MDB_BAD_VALSIZE => error.UnsupportedSize,
        c.MDB_BAD_DBI => error.BadDatabaseHandle,
        @enumToInt(os.E.NOENT) => error.NoSuchFileOrDirectory,
        @enumToInt(os.E.IO) => error.InputOutputError,
        @enumToInt(os.E.NOMEM) => error.OutOfMemory,
        @enumToInt(os.E.ACCES) => error.ReadOnly,
        @enumToInt(os.E.BUSY) => error.DeviceOrResourceBusy,
        @enumToInt(os.E.INVAL) => error.InvalidParameter,
        @enumToInt(os.E.NOSPC) => error.NoSpaceLeftOnDevice,
        @enumToInt(os.E.EXIST) => error.FileAlreadyExists,
        else => panic("({}) {s}", .{ rc, c.mdb_strerror(rc) }),
    };
}

test {
    testing.refAllDecls(@This());
}

test "Environment.init() / Environment.deinit(): query environment stats, flags, and info" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{
        .use_writable_memory_map = true,
        .dont_sync_metadata = true,
        .map_size = 4 * 1024 * 1024,
        .max_num_readers = 42,
    });
    defer env.deinit();

    try testing.expectEqualStrings(path, env.path());
    try testing.expect(env.getMaxKeySize() > 0);
    try testing.expect(env.getMaxNumReaders() == 42);

    const stat = env.stat();
    try testing.expect(stat.tree_height == 0);
    try testing.expect(stat.num_branch_pages == 0);
    try testing.expect(stat.num_leaf_pages == 0);
    try testing.expect(stat.num_overflow_pages == 0);
    try testing.expect(stat.num_entries == 0);

    const flags = env.getFlags();
    try testing.expect(flags.use_writable_memory_map == true);
    try testing.expect(flags.dont_sync_metadata == true);

    env.disableFlags(.{ .dont_sync_metadata = true });
    try testing.expect(env.getFlags().dont_sync_metadata == false);

    env.enableFlags(.{ .dont_sync_metadata = true });
    try testing.expect(env.getFlags().dont_sync_metadata == true);

    const info = env.info();
    try testing.expect(info.map_address == null);
    try testing.expect(info.map_size == 4 * 1024 * 1024);
    try testing.expect(info.last_page_num == 1);
    try testing.expect(info.last_tx_id == 0);
    try testing.expect(info.max_num_reader_slots > 0);
    try testing.expect(info.num_used_reader_slots == 0);

    try env.setMapSize(8 * 1024 * 1024);
    try testing.expect(env.info().map_size == 8 * 1024 * 1024);

    // The file descriptor should be >= 0.

    try testing.expect(env.fd() >= 0);

    try testing.expect((try env.purge()) == 0);
}

test "Environment.copyTo(): backup environment and check environment integrity" {
    var tmp_a = testing.tmpDir(.{});
    defer tmp_a.cleanup();

    var tmp_b = testing.tmpDir(.{});
    defer tmp_b.cleanup();

    var buf_a: [fs.MAX_PATH_BYTES]u8 = undefined;
    var buf_b: [fs.MAX_PATH_BYTES]u8 = undefined;

    var path_a = try tmp_a.dir.realpath("./", &buf_a);
    var path_b = try tmp_b.dir.realpath("./", &buf_b);

    const env_a = try Environment.init(path_a, .{});
    {
        defer env_a.deinit();

        const tx = try env_a.begin(.{});
        errdefer tx.deinit();

        const db = try tx.open(.{});
        defer db.close(env_a);

        var i: u8 = 0;
        while (i < 128) : (i += 1) {
            try tx.put(db, &[_]u8{i}, &[_]u8{i}, .{ .dont_overwrite_key = true });
            try testing.expectEqualStrings(&[_]u8{i}, try tx.get(db, &[_]u8{i}));
        }

        try tx.commit();
        try env_a.copyTo(path_b, .{ .compact = true });
    }

    const env_b = try Environment.init(path_b, .{});
    {
        defer env_b.deinit();

        const tx = try env_b.begin(.{});
        defer tx.deinit();

        const db = try tx.open(.{});
        defer db.close(env_b);

        var i: u8 = 0;
        while (i < 128) : (i += 1) {
            try testing.expectEqualStrings(&[_]u8{i}, try tx.get(db, &[_]u8{i}));
        }
    }
}

test "Environment.sync(): manually flush system buffers" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{
        .dont_sync = true,
        .dont_sync_metadata = true,
        .use_writable_memory_map = true,
    });
    defer env.deinit();

    {
        const tx = try env.begin(.{});
        errdefer tx.deinit();

        const db = try tx.open(.{});
        defer db.close(env);

        var i: u8 = 0;
        while (i < 128) : (i += 1) {
            try tx.put(db, &[_]u8{i}, &[_]u8{i}, .{ .dont_overwrite_key = true });
            try testing.expectEqualStrings(&[_]u8{i}, try tx.get(db, &[_]u8{i}));
        }

        try tx.commit();
        try env.sync(true);
    }

    {
        const tx = try env.begin(.{});
        defer tx.deinit();

        const db = try tx.open(.{});
        defer db.close(env);

        var i: u8 = 0;
        while (i < 128) : (i += 1) {
            try testing.expectEqualStrings(&[_]u8{i}, try tx.get(db, &[_]u8{i}));
        }
    }
}

test "Transaction: get(), put(), reserve(), delete(), and commit() several entries with dont_overwrite_key = true / false" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{});
    defer env.deinit();

    const tx = try env.begin(.{});
    errdefer tx.deinit();

    const db = try tx.open(.{});
    defer db.close(env);

    // Transaction.put() / Transaction.get()

    try tx.put(db, "hello", "world", .{});
    try testing.expectEqualStrings("world", try tx.get(db, "hello"));

    // Transaction.put() / Transaction.reserve() / Transaction.get() (.{ .dont_overwrite_key = true })

    try testing.expectError(error.AlreadyExists, tx.put(db, "hello", "world", .{ .dont_overwrite_key = true }));
    {
        const result = try tx.reserve(db, "hello", "world".len, .{ .dont_overwrite_key = true });
        try testing.expectEqualStrings("world", result.found_existing);
    }
    try testing.expectEqualStrings("world", try tx.get(db, "hello"));

    // Transaction.put() / Transaction.get() / Transaction.reserve() (.{ .dont_overwrite_key = false })

    try tx.put(db, "hello", "other_value", .{});
    try testing.expectEqualStrings("other_value", try tx.get(db, "hello"));
    {
        const result = try tx.reserve(db, "hello", "new_value".len, .{});
        try testing.expectEqual("new_value".len, result.successful.len);
        mem.copy(u8, result.successful, "new_value");
    }
    try testing.expectEqualStrings("new_value", try tx.get(db, "hello"));

    // Transaction.del() / Transaction.get() / Transaction.put() / Transaction.get()

    try tx.del(db, "hello", .key);

    try testing.expectError(error.NotFound, tx.del(db, "hello", .key));
    try testing.expectError(error.NotFound, tx.get(db, "hello"));

    try tx.put(db, "hello", "world", .{});
    try testing.expectEqualStrings("world", try tx.get(db, "hello"));

    // Transaction.commit()

    try tx.commit();
}

test "Transaction: reserve, write, and attempt to reserve again with dont_overwrite_key = true" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{});
    defer env.deinit();

    const tx = try env.begin(.{});
    errdefer tx.deinit();

    const db = try tx.open(.{});
    defer db.close(env);

    switch (try tx.reserve(db, "hello", "world!".len, .{ .dont_overwrite_key = true })) {
        .found_existing => try testing.expect(false),
        .successful => |dst| std.mem.copy(u8, dst, "world!"),
    }

    switch (try tx.reserve(db, "hello", "world!".len, .{ .dont_overwrite_key = true })) {
        .found_existing => |src| try testing.expectEqualStrings("world!", src),
        .successful => try testing.expect(false),
    }

    try tx.commit();
}

test "Transaction: getOrPut() twice" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{});
    defer env.deinit();

    const tx = try env.begin(.{});
    errdefer tx.deinit();

    const db = try tx.open(.{});
    defer db.close(env);

    try testing.expectEqual(@as(?[]const u8, null), try tx.getOrPut(db, "hello", "world"));
    try testing.expectEqualStrings("world", try tx.get(db, "hello"));
    try testing.expectEqualStrings("world", (try tx.getOrPut(db, "hello", "world")) orelse unreachable);

    try tx.commit();
}

test "Transaction: use multiple named databases in a single transaction" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{ .max_num_dbs = 2 });
    defer env.deinit();

    {
        const tx = try env.begin(.{});
        errdefer tx.deinit();

        const a = try tx.use("A", .{ .create_if_not_exists = true });
        defer a.close(env);

        const b = try tx.use("B", .{ .create_if_not_exists = true });
        defer b.close(env);

        try tx.put(a, "hello", "this is in A!", .{});
        try tx.put(b, "hello", "this is in B!", .{});

        try tx.commit();
    }

    {
        const tx = try env.begin(.{});
        errdefer tx.deinit();

        const a = try tx.use("A", .{});
        defer a.close(env);

        const b = try tx.use("B", .{});
        defer b.close(env);

        try testing.expectEqualStrings("this is in A!", try tx.get(a, "hello"));
        try testing.expectEqualStrings("this is in B!", try tx.get(b, "hello"));

        try tx.commit();
    }
}

test "Transaction: nest transaction inside transaction" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{});
    defer env.deinit();

    const parent = try env.begin(.{});
    errdefer parent.deinit();

    const db = try parent.open(.{});
    defer db.close(env);

    {
        const child = try env.begin(.{ .parent = parent });
        errdefer child.deinit();

        // Parent ID is equivalent to Child ID. Parent is not allowed to perform
        // operations while child has yet to be aborted / committed.

        try testing.expectEqual(parent.id(), child.id());

        // Operations cannot be performed against a parent transaction while a child
        // transaction is still active.

        try testing.expectError(error.TransactionNotAborted, parent.get(db, "hello"));

        try child.put(db, "hello", "world", .{});
        try child.commit();
    }

    try testing.expectEqualStrings("world", try parent.get(db, "hello"));
    try parent.commit();
}

test "Transaction: custom key comparator" {
    const Descending = struct {
        fn order(a: []const u8, b: []const u8) math.Order {
            return switch (mem.order(u8, a, b)) {
                .eq => .eq,
                .lt => .gt,
                .gt => .lt,
            };
        }
    };

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{ .max_num_dbs = 2 });
    defer env.deinit();

    const tx = try env.begin(.{});
    errdefer tx.deinit();

    const db = try tx.open(.{});
    defer db.close(env);

    const items = [_][]const u8{ "a", "b", "c" };

    try tx.setKeyOrder(db, Descending.order);

    for (items) |item| {
        try tx.put(db, item, item, .{ .dont_overwrite_key = true });
    }

    {
        const cursor = try tx.cursor(db);
        defer cursor.deinit();

        var i: usize = 0;
        while (try cursor.next()) |item| : (i += 1) {
            try testing.expectEqualSlices(u8, items[items.len - 1 - i], item.key);
            try testing.expectEqualSlices(u8, items[items.len - 1 - i], item.val);
        }
    }

    try tx.commit();
}

test "Cursor: move around a database and add / delete some entries" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{});
    defer env.deinit();

    const tx = try env.begin(.{});
    errdefer tx.deinit();

    const db = try tx.open(.{});
    defer db.close(env);

    {
        const cursor = try tx.cursor(db);
        defer cursor.deinit();

        const items = [_][]const u8{ "a", "b", "c" };

        // Cursor.put()

        inline for (items) |item| {
            try cursor.put(item, item, .{ .dont_overwrite_key = true });
        }

        // Cursor.current() / Cursor.first() / Cursor.last() / Cursor.next() / Cursor.prev()

        {
            const last_item = try cursor.last();
            try testing.expectEqualStrings(items[items.len - 1], last_item.?.key);
            try testing.expectEqualStrings(items[items.len - 1], last_item.?.val);

            {
                var i: usize = items.len - 1;
                while (true) {
                    const item = (try cursor.prev()) orelse break;
                    try testing.expectEqualStrings(items[i - 1], item.key);
                    try testing.expectEqualStrings(items[i - 1], item.val);
                    i -= 1;
                }
            }

            const current = try cursor.current();
            const first_item = try cursor.first();
            try testing.expectEqualStrings(items[0], first_item.?.key);
            try testing.expectEqualStrings(items[0], first_item.?.val);
            try testing.expectEqualStrings(first_item.?.key, current.?.key);
            try testing.expectEqualStrings(first_item.?.val, current.?.val);

            {
                var i: usize = 1;
                while (true) {
                    const item = (try cursor.next()) orelse break;
                    try testing.expectEqualStrings(items[i], item.key);
                    try testing.expectEqualStrings(items[i], item.val);
                    i += 1;
                }
            }
        }

        // Cursor.delete()

        try cursor.del(.key);
        while (try cursor.prev()) |_| try cursor.del(.key);
        try testing.expectError(error.NotFound, cursor.del(.key));
        try testing.expect((try cursor.current()) == null);

        // Cursor.put() / Cursor.updateInPlace() / Cursor.reserveInPlace()

        inline for (items) |item| {
            try cursor.put(item, item, .{ .dont_overwrite_key = true });

            try cursor.updateInPlace(item, "???");
            try testing.expectEqualStrings("???", (try cursor.current()).?.val);

            mem.copy(u8, try cursor.reserveInPlace(item, item.len), item);
            try testing.expectEqualStrings(item, (try cursor.current()).?.val);
        }

        // Cursor.seekTo()

        try testing.expectError(error.NotFound, cursor.seekTo("0"));
        try testing.expectEqualStrings(items[items.len / 2], try cursor.seekTo(items[items.len / 2]));

        // Cursor.seekFrom()

        try testing.expectEqualStrings(items[0], (try cursor.seekFrom("0")).val);
        try testing.expectEqualStrings(items[items.len / 2], (try cursor.seekFrom(items[items.len / 2])).val);
        try testing.expectError(error.NotFound, cursor.seekFrom("z"));
        try testing.expectEqualStrings(items[items.len - 1], (try cursor.seekFrom(items[items.len - 1])).val);
    }

    try tx.commit();
}

test "Cursor: interact with variable-sized items in a database with duplicate keys" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{ .max_num_dbs = 1 });
    defer env.deinit();

    const tx = try env.begin(.{});
    errdefer tx.deinit();

    const db = try tx.open(.{ .allow_duplicate_keys = true });
    defer db.close(env);

    const expected = comptime .{
        .{ "Another Set C", [_][]const u8{ "be", "ka", "kra", "tan" } },
        .{ "Set A", [_][]const u8{ "a", "kay", "zay" } },
        .{ "Some Set B", [_][]const u8{ "bru", "ski", "vle" } },
    };

    inline for (expected) |entry| {
        inline for (entry[1]) |val| {
            try tx.putItem(db, entry[0], val, .{ .dont_overwrite_item = true });
        }
    }

    {
        const cursor = try tx.cursor(db);
        defer cursor.deinit();

        comptime var i = 0;
        comptime var j = 0;

        inline while (i < expected.len) : ({
            i += 1;
            j = 0;
        }) {
            inline while (j < expected[i][1].len) : (j += 1) {
                const maybe_entry = try cursor.next();
                const entry = maybe_entry orelse unreachable;

                try testing.expectEqualStrings(expected[i][0], entry.key);
                try testing.expectEqualStrings(expected[i][1][j], entry.val);
            }
        }
    }

    try tx.commit();
}

test "Cursor: interact with batches of fixed-sized items in a database with duplicate keys" {
    const U64 = struct {
        fn order(a: []const u8, b: []const u8) math.Order {
            const num_a = mem.bytesToValue(u64, a[0..8]);
            const num_b = mem.bytesToValue(u64, b[0..8]);
            if (num_a < num_b) return .lt;
            if (num_a > num_b) return .gt;
            return .eq;
        }
    };

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    var path = try tmp.dir.realpath("./", &buf);

    const env = try Environment.init(path, .{ .max_num_dbs = 1 });
    defer env.deinit();

    const tx = try env.begin(.{});
    errdefer tx.deinit();

    const db = try tx.open(.{
        .allow_duplicate_keys = true,
        .duplicate_entries_are_fixed_size = true,
    });
    defer db.close(env);

    try tx.setItemOrder(db, U64.order);

    comptime var items: [512]u64 = undefined;
    inline for (items) |*item, i| item.* = @as(u64, i);

    const expected = comptime .{
        .{ "Set A", &items },
        .{ "Set B", &items },
    };

    {
        const cursor = try tx.cursor(db);
        defer cursor.deinit();

        inline for (expected) |entry| {
            try testing.expectEqual(entry[1].len, try cursor.putBatch(entry[0], entry[1], .{}));
        }
    }

    {
        const cursor = try tx.cursor(db);
        defer cursor.deinit();

        inline for (expected) |expected_entry| {
            const maybe_entry = try cursor.next();
            const entry = maybe_entry orelse unreachable;
            try testing.expectEqualStrings(expected_entry[0], entry.key);

            var i: usize = 0;

            while (try cursor.nextPage(u64)) |page| {
                for (page.items) |item| {
                    try testing.expectEqual(expected_entry[1][i], item);
                    i += 1;
                }
            }
        }
    }

    try tx.commit();
}
