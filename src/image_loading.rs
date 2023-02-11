use anyhow::Context;
use exr::prelude::{self as exrs, ReadChannels as _, ReadLayers as _};
use std::path::Path;

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

    #[inline(always)]
    fn put_pixel(&mut self, x: usize, y: usize, rgb: [f32; 3]) {
        let offset = (y * self.size[0] + x) * 3;
        self.data[offset..offset + 3].copy_from_slice(&rgb);

        /*unsafe {
            let dst = self.data.as_mut_ptr().add(offset);
            *dst = rgb[0];
            *dst.add(1) = rgb[1];
            *dst.add(2) = rgb[2];
        }*/
    }
}

pub fn load_image(file_path: impl AsRef<Path>) -> anyhow::Result<ImageRgb32f> {
    let path = file_path.as_ref();
    let ext = path
        .extension()
        .map(|ext| ext.to_string_lossy().as_ref().to_owned());

    match ext.as_deref() {
        Some("exr") => load_exr(path),
        Some("hdr") => load_hdr(path),
        _ => Err(anyhow::anyhow!("Unsupported file extension: {:?}", ext)),
    }
}

fn load_hdr(file_path: &Path) -> anyhow::Result<ImageRgb32f> {
    let image = radiant::load(std::io::Cursor::new(
        std::fs::read(file_path).context("failed to open specified file")?,
    ))
    .context("failed to load image data")?;

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

    //let t0 = std::time::Instant::now();
    let contents = std::fs::read(file_path)?;
    // println!("Reading the file took {:?}", t0.elapsed());

    //let t0 = std::time::Instant::now();
    // an image that contains a single layer containing an png rgba buffer
    let maybe_image: Result<
        exrs::Image<exrs::Layer<exrs::SpecificChannels<ImageRgb32f, exrs::RgbChannels>>>,
        exrs::Error,
    > = reader.from_unbuffered(std::io::Cursor::new(contents));
    // println!("Rendering the image took {:?}", t0.elapsed());

    let output = maybe_image?.layer_data.channel_data.pixels;
    Ok(output)
}
