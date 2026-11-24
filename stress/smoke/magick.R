# magick (row smoke `@magick.R`): ImageMagick's version; on Windows also an
# SVG read through the downloaded bundle's librsvg, whose Rust objects are
# built with Control Flow Guard (chore-release-12 CI7, O-D11: CFG code run
# on windows-11-arm), and checked by its size.
cfg <- magick_config()
print(cfg[c("version", "rsvg", "cairo", "fontconfig")])
if (.Platform$OS.type == "windows") {
  svg <- '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="10"><rect width="20" height="10" fill="red"/></svg>'
  info <- image_info(image_read(charToRaw(svg)))
  print(info)
  isTRUE(cfg$rsvg) && info$width == 20 && info$height == 10
} else nzchar(as.character(cfg$version))
