# lmdb-zig

Lightweight, fully-featured, idiomatic cross-platform [Zig](https://ziglang.org) bindings to [Lighting Memory-Mapped Database (LMDB)](http://www.lmdb.tech/doc/).

LMDB is a tiny, extraordinarily fast Btree-based embedded KV database with some excellent properties:
- Zero-copy lookup and iteration: the entire database is memory-mapped.
- Transactions may create, drop, and interact with multiple named databases at once.
- Multiple readers, single writer. Writers don't block readers, readers don't block writers.
- Keys are lexicographically sorted by default. A custom key ordering may be defined per named database.
- Zero maintenance: does not require any compaction, external processes, or background threads running.
- Entire database is exposed as a single file accompanied by a lockfile. A single database file may comprise of multiple named databases.
- Fully exploits the operating system's buffer cache given its memory mapping and compact size being a mere 32KB worth of object code.

Refer to the 12 extensive unit tests provided [here](lmdb.zig#L880) for usage instructions and guidelines. 

Built and tested against Zig's master branch over all possible optimization modes.


## Motivation

These bindings were built in mind for utilizing LMDB as the underlying backend of a database project.

As a result, extensive effort was put into exposing and testing as many different aspects of LMDB's functionality as possible with an emphasis on minimal overhead, such as fixed memory map addressing, in-place cursor updates, duplicate keys, on-the-fly backups, crash recovery, etc.

## Setup

These bindings were built with first-class support for the [zigmod](https://github.com/nektro/zigmod) package manager.

To incorporate these bindings into your project, include the following into your project's `zig.mod`:

```yml
- type: git
  path: https://github.com/lithdew/lmdb-zig
```

Afterwards, run:

```shell
zigmod fetch
```

## Status

Presently, these bindings completely cover the entire API surface for LMDB except for the list of methods provided below that were deemed unnecessary. In the case you require any of these methods exported, please file an issue describing your use case.

- [mdb_env_set_userctx](http://www.lmdb.tech/doc/group__mdb.html#gaf2fe09eb9c96eeb915a76bf713eecc46)
- [mdb_env_get_userctx](http://www.lmdb.tech/doc/group__mdb.html#ga45df6a4fb150cda2316b5ae224ba52f1)
- [mdb_cmp](http://www.lmdb.tech/doc/group__mdb.html#gaba790a2493f744965b810efac73bac0e)
- [mdb_dcmp](http://www.lmdb.tech/doc/group__mdb.html#gac61d3087282b0824c8c5caff6caabdf3)
- [mdb_reader_list](http://www.lmdb.tech/doc/group__mdb.html#ga8550000cd0501a44f57ee6dff0188744)
- [mdb_set_relfunc](http://www.lmdb.tech/doc/group__mdb.html#ga697d82c7afe79f142207ad5adcdebfeb)
- [mdb_set_relctx](http://www.lmdb.tech/doc/group__mdb.html#ga7c34246308cee01724a1839a8f5cc594)
 
