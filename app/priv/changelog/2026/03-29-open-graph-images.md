%{
  version: "0.1.0",
  title: "Open Graph image generation",
  description: "Links to Micelio now unfurl with rich preview images on platforms like Slack, Discord, and X.",
  categories: ["feature"],
  author: :pedro
}

---

When you share a link to a Micelio instance on platforms like Slack, Discord, or X, it now unfurls with a rich preview image showing the page title, description, and author.

Images are generated on demand using [Carta](https://github.com/pepicrft/carta), which renders HTML templates into JPEG images via a pool of headless Chromium instances. Once generated, images are cached in storage so subsequent requests are served instantly.

### How it works

Every page that sets metadata (title, description, canonical URL) automatically gets an Open Graph image. The image URL is content-addressed: when the page content changes, a new image is generated.

For blog posts, the author's Gravatar avatar and name appear in the image footer.

### Self-hosting

Open Graph image generation is opt-in in production. Set `MICELIO_OPEN_GRAPH_ENABLED=true` and ensure Chromium is installed. The pool size is configurable via `MICELIO_OPEN_GRAPH_POOL_SIZE`.
