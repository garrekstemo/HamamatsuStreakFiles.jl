# HamamatsuStreakFiles.jl

Standalone reader for Hamamatsu HPD-TA/HiPic `.img` (ITEX) streak-camera files.

- `StreakImage(path)` is the only public entry point; internals are
  underscore-prefixed and unexported. Browse `src/` (`parser.jl`, `binary.jl`,
  `types.jl`) for the implementation; usage examples are in `README.md`.
- Authoritative byte-layout / dtype-table / scaling spec:
  `docs/superpowers/specs/2026-06-09-hamamatsu-img-reader-design.md`.
- Wavelength axis preserves on-disk order (commonly DESCENDING). Never sort or
  flip in the reader; only the Makie ext flips display copies (it reverses both
  `wavelength` and `counts` for the heatmap).
- The `.img` dtype table (code 0 = UInt8, code 1 = compressed) must NOT be
  reused for future `.his` support — the `.his` `dataType` enum differs there
  (code 1 = UInt8). See the note in `src/binary.jl`.
- Tests are synthetic (`make_img` builder in `test/runtests.jl`); no real
  instrument file is committed. Real-file ground truth lives at
  `QPSTools.jl/data/PL/15K.img`.
