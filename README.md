<!-- Allow this file to not have a first line heading -->
<!-- markdownlint-disable-file MD041 -->

<!-- inline html -->
<!-- markdownlint-disable-file MD033 -->

<div align="center">
  
# 🌈🙈 notorious6

Experiments in mapping HDR stimulus to display via shaders and stuff.
  
![screenshot](https://user-images.githubusercontent.com/16522064/155857613-7e9c4ff6-9cab-4007-8174-046807f26014.jpg)

</div>

## Building and running

Should work on Windows and Linux (🐧 not tested yet). Mac will probably throw a fit due to the use of OpenGL.

1. [Get Rust](https://www.rust-lang.org/tools/install).
2. Clone the repo and run `cargo build --release` or `cargo run --release`

The compiled binary sits in `target/release/notorious6`

By default, the app loads images from a folder called `img`. To change it, pass the folder to the app as a parameter, for example:

`cargo run --release -- some_other_folder_or_image`

or

`target/release/notorious6 some_other_folder_or_image`

## Controls

* Left/right - switch images
* Up/down - switch techniques (see the [`shaders`](shaders) folder)
* Hold the left mouse button and drag up/down: change EV

## Acknowledgments

Special thanks to Troy Sobotka for guidance and mind-bending discussions about color.

## License

This contribution is dual licensed under EITHER OF

* Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or <http://www.apache.org/licenses/LICENSE-2.0>)
* MIT license ([LICENSE-MIT](LICENSE-MIT) or <http://opensource.org/licenses/MIT>)

at your option.
