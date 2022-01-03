use exr::prelude::{self as exrs, ReadChannels as _, ReadLayers as _};
use std::path::Path;

pub struct Rgb32fImage {
    pub size: [usize; 2],
    pub data: Vec<f32>,
}

impl Rgb32fImage {
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

pub fn load_exr(file_path: impl AsRef<Path>) -> anyhow::Result<Rgb32fImage> {
    let reader = exrs::read()
        .no_deep_data()
        .largest_resolution_level()
        .rgb_channels(
            |resolution, _channels: &exrs::RgbChannels| -> Rgb32fImage {
                Rgb32fImage::new(resolution.width(), resolution.height())
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
        exrs::Image<exrs::Layer<exrs::SpecificChannels<Rgb32fImage, exrs::RgbChannels>>>,
        exrs::Error,
    > = reader.from_file(file_path);

    let output = maybe_image?.layer_data.channel_data.pixels;
    Ok(output)
}
