# Contributing

Thanks for wanting to help. Bug reports, ideas and pull requests are welcome.

## Before you start

- Check [docs/ROADMAP.md](docs/ROADMAP.md) and open issues, so work is not done twice.
- For anything bigger than a small fix, open an issue first to agree on the approach.

## Pull requests

- Keep one change per pull request, with a clear description of what it changes and why.
- Build the app (`tools/wsl-run.sh build`) and run the engine test
  (`cd engine && go test -tags nosqlite ./...`) before submitting.
- Say how you checked the change on a real device, if you could.
- Match the style of the surrounding code. User-facing strings go through `t("français", "English")`.
- Do not add content sources, extension repositories or links to them. Nami ships without sources.

## Known pitfalls

- Do not use Swift task groups (`withTaskGroup`, `withThrowingTaskGroup`). Built with the current
  toolchain they abort in the iOS 27.2 concurrency runtime. Use separate `Task`s and await their values.
- The engine must be built with `-tags nosqlite` (the build script does it).

## License

By contributing, you agree that your contributions are licensed under the
[GPL-3.0](LICENSE), like the rest of the project.
