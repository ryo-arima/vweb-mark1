# vweb-mark1 Basic Design

The Basic Design is published as one bilingual mdBook on GitHub Pages:

- [English book](./en/)
- [Japanese book](./jp/)

The single mdBook source is split into language trees under
[`src/en/`](src/en/index.md) and [`src/jp/`](src/jp/index.md), with one shared
[`SUMMARY.md`](src/SUMMARY.md).

Build the book with:

```bash
mdbook build docs
```

Start a local preview with:

```bash
mdbook serve docs --open
```

