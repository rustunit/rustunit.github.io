+++
title = "Rust crate feature debugging"
date = 2024-12-12
[extra]
tags=["rust","bevy","cargo"] 
hidden = false
custom_summary = "Figure out what enabled a feature in a crate in your dependencies breaking your build."
+++

In this short post we look at how to debug a recent build breakage we encountered due to a *feature* being enabled on one of our dependencies that is not compatible with our build target: **wasm**.

# What happened

After porting our bevy based game [tinytakeoff](https://tinytakeoff.com) to the newest bvy release: [0.15](https://bevyengine.org/news/bevy-0-15/)

```sh
cargo:warning=In file included from vendor/basis_universal/encoder/pvpngreader.cpp:14:
  cargo:warning=vendor/basis_universal/encoder/../transcoder/basisu.h:53:10: fatal error: 'stdlib.h' file not found
  cargo:warning=   53 | #include <stdlib.h>
  cargo:warning=      |          ^~~~~~~~~~
  cargo:warning=1 error generated.
```

# How to find the cause

`cargo tree -e features`:

```sh
├── winit v0.30.5
│   ├── tracing v0.1.41
│   │   ├── tracing-core v0.1.33
│   │   │   └── once_cell feature "default"
│   │   │       ├── once_cell v1.20.2
│   │   │       └── once_cell feature "std"
│   │   │           ├── once_cell v1.20.2
│   │   │           └── once_cell feature "alloc"
│   │   │               ├── once_cell v1.20.2
│   │   │               └── once_cell feature "race"
│   │   │                   └── once_cell v1.20.2
│   │   ├── pin-project-lite feature "default"
│   │   │   └── pin-project-lite v0.2.15
│   │   └── tracing-attributes feature "default"
│   │       └── tracing-attributes v0.1.28 (proc-macro)
```

```sh
├── bevy_libgdx_atlas feature "default"
│   └── bevy_libgdx_atlas v0.3.0
│       ├── bevy feature "basis-universal"
│       │   ├── bevy v0.15.0 (*)
```

`cargo tree -e features -p bevy --invert`:

```sh
├── bevy feature "basis-universal"
│   └── bevy_libgdx_atlas v0.3.0
│       └── bevy_libgdx_atlas feature "default"
│           └── tinytakeoff v0.1.1
```

# How to make this more ergonomic

* `cargo tree` should generate a computer readable format
* a `cargo tree-tui` would be nice, allowing to interactively inspect dependencies, their features and fan in (who uses it) and fan out (what it is using)

---

Do you need support building your Bevy or Rust project? Our team of experts can support you! [Contact us.](@/contact.md)