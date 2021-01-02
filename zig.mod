id: uyw3xk95w7nrelwn86xop56d8v8w2wocqdrpuqnu9ylx4n3n
name: lmdb
main: lmdb.zig
dependencies:
    - type: git
      path: https://github.com/LMDB/lmdb
      version: tag-LMDB_0.9.24
      c_include_dirs:
        - libraries/liblmdb
      c_source_files:
        - libraries/liblmdb/mdb.c
        - libraries/liblmdb/midl.c
      c_source_flags: [-pthread, -fno-sanitize=undefined]