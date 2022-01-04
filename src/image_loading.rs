use anyhow::Context;
use exr::prelude::{self as exrs, ReadChannels as _, ReadLayers as _};
use std::{fs::File, io::BufReader, path::Path};

pub struct ImageRgb32f {
    pub size: [usize; 2],
    pub data: Vec<f32>,
}

impl ImageRgb32f {
    pub fn new(width: usize, height: usize) -> Self {
        Self {
            size: [width, height],
            data: vec![0.0; width * height * 3],
        }
    }

    fn put_pixel(&mut self, x: usize, y: usize, rgb: [f32; 3]) {
        let offset = (y * self.size[0] + x) * 3;
        self.data[offset..offset + 3].copy_from_slice(&rgb);
    }
}

pub fn load_image(file_path: impl AsRef<Path>) -> anyhow::Result<ImageRgb32f> {
    let path = file_path.as_ref();
    let ext = path
        .extension()
        .map(|ext| ext.to_string_lossy().as_ref().to_owned());

    match ext.as_ref().map(String::as_str) {
        Some("exr") => load_exr(path),
        Some("hdr") => load_hdr(path),
        _ => Err(anyhow::anyhow!("Unsupported file extension: {:?}", ext)),
    }
}

fn load_hdr(file_path: &Path) -> anyhow::Result<ImageRgb32f> {
    let f = File::open(&file_path).context("failed to open specified file")?;
    let f = BufReader::new(f);
    let image = radiant::load(f).context("failed to load image data")?;

    let data: Vec<f32> = image
        .data
        .iter()
        .copied()
        .flat_map(|px| [px.r, px.g, px.b].into_iter())
        .collect();

    Ok(ImageRgb32f {
        size: [image.width, image.height],
        data,
    })
}

fn load_exr(file_path: &Path) -> anyhow::Result<ImageRgb32f> {
    let reader = exrs::read()
        .no_deep_data()
        .largest_resolution_level()
        .rgb_channels(
            |resolution, _channels: &exrs::RgbChannels| -> ImageRgb32f {
                ImageRgb32f::new(resolution.width(), resolution.height())
            },
            // set each pixel in the png buffer from the exr file
            |output, position, (r, g, b): (f32, f32, f32)| {
                output.put_pixel(position.0, position.1, [r, g, b]);
            },
        )
        .first_valid_layer()
        .all_attributes();

    // an image that contains a single layer containing an png rgba buffer
    let maybe_image: Result<
        exrs::Image<exrs::Layer<exrs::SpecificChannels<ImageRgb32f, exrs::RgbChannels>>>,
        exrs::Error,
    > = reader.from_file(file_path);

    let output = maybe_image?.layer_data.channel_data.pixels;
    Ok(output)
}
