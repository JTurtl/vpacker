# **VPacker**
### CLI tool to make and unpack Valve VPK files

## **Building from source**
Requirements:
- Recent Zig compiler (v0.11.0-dev, [https://ziglang.org/download](https://ziglang.org/download/))

Build commands:
```sh
~$ git clone https://github.com/jturtl/vpacker
~$ cd vpacker
vpacker$ zig build
# static executable at ./zig-out/bin/vpacker
```

## **Compatibility**
Supports only Version 2 VPK files.
Almost all existing VPKs are Version 2.

Does not work with Titanfall 2.

## **Usage**
```sh
vpacker $command $args
```
Where `$command` is one of:
`list extract pack unpack check`

`$args` depends on the command.

All commands that need an existing archive expect that archive to be the *index file*. If the file name ends with `_dir.vpk` and there are other files named like `archive_000.vpk`, `archive_001.vpk`, etc., then the *index file* is the one that ends with `_dir.vpk`. 

If the file does not match the above naming scheme, then it is an *independent index file*, and can be used like any other index file.

VPacker accepts files up to 2GB (2^31 bytes, maximum addressable space with a signed 32-bit integer), but in practice all VPK files are less than 200MiB.

## **Commands**
### **List:**
Write to stdout all files contained in this archive:
```sh
~$ vpacker list $archive.vpk
```

Example:
```sh
~$ vpacker list mystuff.vpk
materials/crowbar.vtf
materials/crowbar.vmt
models/crowbar.mdl
models/crowbar.vvd
models/crowbar.vtx
```

### **Extract:**
Extract specific files from an archive into the current directory:
```sh
~$ vpacker extract $archive.vpk $files
```
Example:
```sh
~$ vpacker extract $hl2/hl2_misc_dir.vpk models/error.mdl models/error.vvd models/error.dx90.vtx
~$ ls
error.mdl error.vvd error.dx90.vtx
```
This command will fail if:
- One or more files do not exist in the archive
- One or more files have matching names
  - ex: `this/file.txt` and `that/file.txt` collide
- A file already exists with one of the file names
  - ex: cannot extract `this/file.txt` if `file.txt` exists in the current directory

### **Pack:**
Pack a directory into one or more archives
```sh
~$ vpacker pack $dir
```
Example:
```sh
~$ ls
mystuff/
~$ ls mystuff
randomfile.txt models/ materials/
~$ ls mystuff/models
crowbar.mdl crowbar.vvd crowbar.vtx
~$ ls mystuff/materials
crowbar.vmt crowbar.vtf
~$ vpacker pack mystuff
~$ ls
mystuff/ mystuff.vpk
~$ vpacker list mystuff.vpk
randomfile.txt
models/crowbar.mdl
models/crowbar.vvd
models/crowbar.vtx
materials/crowbar.vmt
materials/crowbar.vtf
```
The archive may be split into multiple files (`_dir.vpk`, `_000.vpk`, etc) if it is not possible to store all of the data in a single file less than 200MiB.

### **Unpack:**
Extract all files from an archive into a new directory
```sh
~$ vpacker unpack $archive.vpk
```
Example:
```sh
~$ ls
mystuff.vpk
~$ vpacker unpack mystuff.vpk
~$ ls
mystuff.vpk mystuff/
~$ ls mystuff
randomfile.txt models/ materials/
```
If a file or directory already exists with the name of the archive, the program will fail.
