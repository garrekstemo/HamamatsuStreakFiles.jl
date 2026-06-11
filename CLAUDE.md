# HamamatsuStreakFiles.jl

Standalone reader for Hamamatsu HPD-TA/HiPic `.img` (ITEX) streak-camera files.
Sibling of JASCOFiles.jl / RigakuFiles.jl; v0.1.0 registration triggered (General PR pending the JuliaRegistrator app being enabled for this repo).

- Design spec: `docs/superpowers/specs/2026-06-09-hamamatsu-img-reader-design.md`
  (byte layout, dtype table, scaling resolution rules — authoritative).
- `StreakImage(path)` is the only public entry point; internals are
  underscore-prefixed and unexported.
- Wavelength axis preserves on-disk order (commonly DESCENDING). Never sort or
  flip in the reader; the Makie ext flips display copies only.
- The `.img` dtype table must NOT be reused for future `.his` support — the
  `.his` dataType enum differs (code 1 = UInt8 there, compressed here).
- Tests are synthetic (`make_img` builder in `test/runtests.jl`); no real
  instrument file is committed. Real-file ground truth lives at
  `QPSTools.jl/data/PL/15K.img` (see plan Task 9).
