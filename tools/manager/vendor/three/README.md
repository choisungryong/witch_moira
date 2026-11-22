# Local 3D character view dependency (three.js)

three.js r187 (npm package `three@0.187.0`), MIT. License text: `LICENSE` in this folder (copied from the package).

Source: official npm registry tarball https://registry.npmjs.org/three/-/three-0.187.0.tgz
(4795351 bytes, sha1 `face29ee2de9bcc31a1b573a76f224e35e0b2894`, equal to the registry's `dist.shasum`).
Downloaded 2026-11-22, once. The screen needs no internet.

Files copied unchanged from the package (this release has no `.min.js`; the module build is split in two files):

| File here | Package path | Bytes | sha256 |
|---|---|---|---|
| `three.module.js` | `build/three.module.js` | 658900 | `104f56145899722094556490d787aae0617cc2fc3382f31df02d724ea1aee341` |
| `three.core.js` | `build/three.core.js` | 1474799 | `613e370f76638fdef83926642bf256dc9615684922de1ce1f63a8583e5d78578` |
| `addons/loaders/GLTFLoader.js` | `examples/jsm/loaders/GLTFLoader.js` | 119861 | `532ac726e120039acbcd6cf54328c57acbf7b438176afaa6951257126d11bff1` |
| `addons/controls/OrbitControls.js` | `examples/jsm/controls/OrbitControls.js` | 40918 | `e7fca2fe9e7670a828af9b28084669a5909445b7f36f1f26cee9bf8f2961c32c` |
| `addons/utils/SkeletonUtils.js` | `examples/jsm/utils/SkeletonUtils.js` | 11535 | `b1632a703206c3d830de9fcbe515696770d04b71a15ee6b50afa6d2c3298c86f` |
| `addons/utils/BufferGeometryUtils.js` | `examples/jsm/utils/BufferGeometryUtils.js` | 39153 | `7bda2a8ba836b2bcf67cb938d4b9e1bb5d1b1bc616817103ed858c0b58296ce7` |
| `LICENSE` | `LICENSE` | 1081 | `8b378ebe60e2fe500158cb0ac71cb5e8b7d92953c2abcc63a0eb90499653b5bc` |

`BufferGeometryUtils.js` is not used by the screen directly; `GLTFLoader.js` imports it.
`three.core.js` is imported by `three.module.js`.

Use: `index.html` has an import map (`three` -> `/vendor/three/three.module.js`, `three/addons/` -> `/vendor/three/addons/`).
`character.js` loads three with `import()` only when the Characters screen opens. The server serves only the file names
listed in `STATIC_EXTRA` (`server.py`). No Draco, KTX2 or Meshopt decoder is set, so compressed models are not supported
and a plain error is shown. Doc comments inside the library mention web addresses; the library makes no request by itself.
To update: download a new release from the official registry, replace the files, and rewrite this table with the new sha256.
