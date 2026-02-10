# Micelio

Micelio is a minimalist and free software git forge. The main instance is available at [micelio.dev](https://micelio.dev).

> [!WARNING]
> This project is a work in progress and exploratory. Expect breaking changes and incomplete features.

## Documentation

The documentation for _users_, _contributors_, and _hosters_ is available at [`/docs`](/docs).

## Development

> [!NOTE]
> Micelio uses [libgit2](https://libgit2.org/) for Git operations via Zig NIFs. You'll need to install it before compiling:
> - **macOS**: `brew install libgit2`
> - **Debian/Ubuntu**: `apt-get install libgit2-dev`
>
> The `mic` CLI vendors gRPC C core version `v1.76.0` in `mic/vendor/grpc`.
> Building the CLI fetches gRPC dependencies into `mic/vendor/grpc/third_party` (no git submodules).

## mic CLI (early access)

```
mic auth login
mic checkout <account>/<project>
mic status
mic land "your goal"
```

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## License

Micelio is licensed under the Mozilla Public License 2.0 (MPL-2.0). See `LICENSE`.
