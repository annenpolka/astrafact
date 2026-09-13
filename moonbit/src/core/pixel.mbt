///|
/// Decoded image pixels as delivered by the platform adapter. `channels` is
/// the number of interleaved bytes per pixel (1=gray, 2=gray+alpha, 3=RGB,
/// 4=RGBA), row-major, top-left origin.
pub(all) struct ImageData {
  pub width : Int
  pub height : Int
  pub channels : Int
  pub data : Bytes
}

///|
pub(all) struct PixelDiff {
  pub changed_pixels : Int
  pub unauthorized_pixels : Int
}

///|
pub fn pixel_diff_allowed(d : PixelDiff) -> Bool {
  d.unauthorized_pixels == 0
}

///|
/// Invisible RGB values are irrelevant to the normalized visual
/// representation: alpha-zero pixels collapse to (0,0,0,0).
fn canonical_pixel(r : Int, g : Int, b : Int, a : Int) -> (Int, Int, Int, Int) {
  if a == 0 {
    (0, 0, 0, 0)
  } else {
    (r, g, b, a)
  }
}

///|
fn pixel_at(img : ImageData, x : Int, y : Int) -> (Int, Int, Int, Int) {
  let i = (y * img.width + x) * img.channels
  let c0 = img.data[i].to_int()
  if img.channels == 1 {
    (c0, c0, c0, 255)
  } else if img.channels == 2 {
    (c0, c0, c0, img.data[i + 1].to_int())
  } else if img.channels == 3 {
    (c0, img.data[i + 1].to_int(), img.data[i + 2].to_int(), 255)
  } else {
    (
      c0,
      img.data[i + 1].to_int(),
      img.data[i + 2].to_int(),
      img.data[i + 3].to_int(),
    )
  }
}

///|
/// Compare decoded pixels, never PNG encoding bytes. `mask` is grayscale L:
/// 255 = editable, 0 = frozen, strictly binary. Caller verifies all unlisted
/// frames separately.
pub fn inspect_patch(
  before : ImageData,
  after : ImageData,
  mask : ImageData,
) -> PixelDiff raise ContractError {
  if before.width != after.width || before.height != after.height || before.width != mask.width || before.height != mask.height {
    raise ContractError("Canvas sizes differ; implicit resizing is forbidden")
  }
  if mask.channels != 1 {
    raise ContractError("Mask must be a grayscale L image")
  }
  let mut mask_binary = true
  for i = 0; i < mask.data.length(); i = i + 1 {
    let v = mask.data[i].to_int()
    if v != 0 && v != 255 {
      mask_binary = false
    }
  }
  if not(mask_binary) {
    raise ContractError("Mask must contain only 0 and 255")
  }
  let mut changed = 0
  let mut unauthorized = 0
  for y = 0; y < before.height; y = y + 1 {
    for x = 0; x < before.width; x = x + 1 {
      let pa = pixel_at(before, x, y)
      let pb = pixel_at(after, x, y)
      if canonical_pixel(pa.0, pa.1, pa.2, pa.3) != canonical_pixel(pb.0, pb.1, pb.2, pb.3) {
        changed = changed + 1
        if mask.data[y * mask.width + x].to_int() == 0 {
          unauthorized = unauthorized + 1
        }
      }
    }
  }
  { changed_pixels: changed, unauthorized_pixels: unauthorized }
}
