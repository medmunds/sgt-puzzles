# sgt-puzzles

This is a fork of [Simon Tatham's Portable Puzzle Collection][upstream]
used in [medmunds/puzzles-web][puzzles-web].

Issues should be reported to the [puzzles-web] repo.

Branches:
* The [`main` branch][main branch] is a mirror of the upstream repo:
  https://git.tartarus.org/simon/puzzles.git
* The default `puzzles-web` branch is some (possibly outdated) version
  of the upstream main branch, with local [modifications](#modifications)
  for the [puzzles-web] PWA build

The upstream readme is [here](./README).

[upstream]: https://www.chiark.greenend.org.uk/~sgtatham/puzzles/
[puzzles-web]: https://github.com/medmunds/puzzles-web
[main branch]: https://github.com/medmunds/sgt-puzzles/tree/main


## Modifications

Review:
* [Local modifications][compare-local] not in upstream
* [Upstream updates][compare-upstream] not yet merged here

In general, commits starting with `puzzles-web:` are specific to the PWA build
and are unlikely to be relevant upstream.

The local modifications are a combination of:

* JS frontend glue for the PWA: see `webapp.cpp` and `cmake/platforms/webapp.cmake`.
  (Compared to `emcc.c`, `emcclib.js`, `emccpre.js` and `emscripten.cmake`,
  the webapp frontend moves more of the implementation from C to JS, and it is
  meant to support multiple instances of puzzles running on the same page.)

* `NARROW_BORDERS` compile option: reduces padding within puzzle rendering to the
  minimum possible (often zero), so padding can be controlled entirely by the frontend.
  Useful for small screens like phones.

* Various bug fixes and features I wanted in particular puzzles. (Many of these
  have been offered as upstream patches.)

* Some midend additions I needed for particular PWA features. (I'll offer these as
  patches once it becomes clear they're useful and designed properly.)

* My [custom fork](https://github.com/medmunds/puzzles-unreleased) of the
  [x-sheep/puzzles-unreleased](https://github.com/x-sheep/puzzles-unreleased) repo,
  as a submodule in `unreleased/`.

* An attempt to automate extraction of license attribution requirements,
  in `emcc-dependency-info.py`.

[compare-local]: https://github.com/medmunds/sgt-puzzles/compare/main...puzzles-web
[compare-upstream]: https://github.com/medmunds/sgt-puzzles/compare/puzzles-web...main
