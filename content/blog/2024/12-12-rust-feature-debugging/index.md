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

After porting our bevy based game [tinytakeoff](https://tinytakeoff.com) to the newest Bevy release: [0.15](https://bevyengine.org/news/bevy-0-15/) our build broke with the following error on **wasm**:

```sh
cargo:warning=In file included from vendor/basis_universal/encoder/pvpngreader.cpp:14:
cargo:warning=vendor/basis_universal/encoder/../transcoder/basisu.h:53:10: fatal error: 'stdlib.h' file not found
cargo:warning=   53 | #include <stdlib.h>
cargo:warning=      |          ^~~~~~~~~~
cargo:warning=1 error generated.
```

So that looks like some crate tries to build some c code under the hood. That is not a problem on native build targets but wont fly on **wasm**. 

This happens in the `basis-universal` crate, what could that be good for? Reading up on it's [crates.io page](https://crates.io/crates/basis-universal) we find out that it is:

> Bindings for Binomial LLC's basis-universal Supercompressed GPU Texture Codec

Looking into the [Bevy Migration Guide for 0.14 to 0.15](https://bevyengine.org/learn/migration-guides/0-14-to-0-15) we find exactly one [place](https://bevyengine.org/learn/migration-guides/0-14-to-0-15/#add-feature-requirement-info-to-image-loading-docs) of it being mentioned: 

<img src="screen1.png" alt="changelog screenshot" class="centered" style="max-width: 70%"/>

So this dependency is for sure nothing we need as we did not start making use of said image format. How did it get introduced?

Let's find the cause for this.

# How to find the cause

We first want to find out where in our tree of dependencies this one is used. `cargo tree` is the tool to help you analyze your dependencies as the graph structure they make up. 

When running `cargo tree` we get get over 1.000 lines of output where we can search for `basis-universal`:

```sh
│       │   ├── bevy_image v0.15.0
│       │   │   ├── basis-universal v0.3.1
│       │   │   │   ├── basis-universal-sys v0.3.1
│       │   │   │   │   [build-dependencies]
│       │   │   │   │   └── cc v1.2.3 (*)
```

We got a winner. It is used by `bevy_image`. The problem is that we do not know why. Based on the changelog linked above we know it is supposed to be behind a `feature` flag called `basis_universal`, looking at our `Cargo.toml` we do not enable it though.

> Cargo will enable the minimum subset of `features` needed so that every dependency using `bevy` get the features they ask for.

The question therefore is: Which crate asks for this feature?

# Playing Cargo Feature Detective

There is a little known feature in `cargo tree` that allows us to not only see our dependency tree but also the features that are enabled in each crate. 

Running `cargo tree -e features` in our repository root we get over 3.000 lines of this:

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

Luckily we know know already what 

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