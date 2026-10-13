# Third-party notices

## JavStrm / Miyabi

The client interoperates with the JavStrm backend supplied by the user:

```text
http://10.10.10.10:33000/sean/JavStrm
```

The following materials are derived from that repository:

- JSON contract fixtures in `Tests/JavStrmCoreTests/Fixtures`, from `internal/api/testdata/golden`.
- The app's J-shaped brand mark and play triangle, from `web/public/favicon.svg`, reproduced by `scripts/generate_icon.swift`.

That project is based on `ppxb/miyabi` and is distributed under GNU GPL version 3. The license text is included in `LICENSE`. This client is distributed under the same license.

All runtime application code uses Apple's system frameworks. No third-party binary libraries, analytics SDKs, or remote package dependencies are included.
