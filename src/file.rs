use anyhow::Context as _;
use bytes::Bytes;
use hotwatch::Hotwatch;
use lazy_static::lazy_static;
use parking_lot::Mutex;
use std::{fs::File, path::PathBuf};
use turbosloth::*;

lazy_static! {
    pub(crate) static ref FILE_WATCHER: Mutex<Hotwatch> =
        Mutex::new(Hotwatch::new_with_custom_delay(std::time::Duration::from_millis(100)).unwrap());
}

#[derive(Clone, Hash)]
pub struct LoadFile {
    path: PathBuf,
}

impl LoadFile {
    pub fn new(path: impl Into<PathBuf>) -> anyhow::Result<Self> {
        let path = path.into().canonicalize()?;
        Ok(Self { path })
    }
}

#[async_trait]
impl LazyWorker for LoadFile {
    type Output = anyhow::Result<Bytes>;

    async fn run(self, ctx: RunContext) -> Self::Output {
        let invalidation_trigger = ctx.get_invalidation_trigger();

        FILE_WATCHER
            .lock()
            .watch(self.path.clone(), move |event| {
                if matches!(event, hotwatch::Event::Write(_)) {
                    invalidation_trigger();
                }
            })
            .with_context(|| format!("LoadFile: trying to watch {:?}", self.path))?;

        let mut buffer = Vec::new();
        std::io::Read::read_to_end(&mut File::open(&self.path)?, &mut buffer)
            .with_context(|| format!("LoadFile: trying to read {:?}", self.path))?;

        Ok(Bytes::from(buffer))
    }

    fn debug_description(&self) -> Option<std::borrow::Cow<'static, str>> {
        Some(format!("LoadFile({:?})", self.path).into())
    }
}
