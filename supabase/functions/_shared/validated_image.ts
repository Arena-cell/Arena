import { ImageMagick, initializeImageMagick, MagickFormat, ResourceLimits } from 'npm:@imagemagick/magick-wasm@0.0.45';

export const imageLimits = { avatars: 3 * 1024 * 1024, 'chat-images': 5 * 1024 * 1024, 'stadium-images': 10 * 1024 * 1024 } as const;
export type ImageBucket = keyof typeof imageLimits;
export class ImageRejected extends Error {
  constructor(public code: string, public status = 400) { super(code); }
}
let initialized: Promise<void> | undefined;
async function initialize() {
  const bytes = await Deno.readFile(new URL(import.meta.resolve('npm:@imagemagick/magick-wasm@0.0.45/magick.wasm')));
  await initializeImageMagick(bytes);
  ResourceLimits.memory = 96n * 1024n * 1024n;
  ResourceLimits.maxMemoryRequest = 64n * 1024n * 1024n;
  ResourceLimits.maxProfileSize = 1024n * 1024n;
  ResourceLimits.disk = 0n;
  ResourceLimits.width = 8192n;
  ResourceLimits.height = 8192n;
  ResourceLimits.area = 16n * 1024n * 1024n;
  // Decoder bookkeeping needs more than one image cache even for a static
  // PNG. Only a single decoded image is emitted by ImageMagick.read below.
  ResourceLimits.listLength = 8n;
}
function signature(bytes: Uint8Array): MagickFormat {
  if (bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) return MagickFormat.Jpeg;
  if ([137,80,78,71,13,10,26,10].every((value, i) => bytes[i] === value)) return MagickFormat.Png;
  if (bytes.length >= 12 && new TextDecoder().decode(bytes.subarray(0,4)) === 'RIFF' && new TextDecoder().decode(bytes.subarray(8,12)) === 'WEBP') return MagickFormat.WebP;
  throw new ImageRejected('IMAGE_TYPE_NOT_ALLOWED');
}
// MIME/filename are intentionally absent. Force the decoder selected from the
// signature, then fully decode, strip metadata and encode a fresh static image.
export async function validateAndOptimizeImage(bytes: Uint8Array, bucket: ImageBucket): Promise<Uint8Array> {
  if (bytes.length === 0) throw new ImageRejected('INVALID_IMAGE');
  if (bytes.length > imageLimits[bucket]) throw new ImageRejected('IMAGE_TOO_LARGE', 413);
  const format = signature(bytes);
  await (initialized ??= initialize());
  try {
    const result = ImageMagick.read(bytes, format, image => {
      if (image.width * image.height > 16 * 1024 * 1024 || image.width < 1 || image.height < 1) throw new ImageRejected('IMAGE_DIMENSIONS_EXCEEDED');
      image.autoOrient();
      const side = bucket === 'avatars' ? 1024 : 2560;
      if (Math.max(image.width, image.height) > side) {
        const scale = side / Math.max(image.width, image.height);
        image.resize(Math.max(1, Math.round(image.width * scale)), Math.max(1, Math.round(image.height * scale)));
      }
      image.strip();
      image.quality = 90;
      return image.write(MagickFormat.WebP, data => new Uint8Array(data));
    });
    if (result.length > imageLimits[bucket]) throw new ImageRejected('IMAGE_TOO_LARGE', 413);
    return result;
  } catch (error) {
    if (error instanceof ImageRejected) throw error;
    throw new ImageRejected('INVALID_IMAGE');
  }
}
