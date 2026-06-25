# BlogLite

A minimal self-hosted blog engine. No database, no build step, no CMS — just markdown and HTML files served dynamically by Caddy. Drop a file in `site/posts/`, it appears on the homepage on the next page load.

## Stack

- **Caddy** — HTTP server with a built-in Go template engine
- **Docker** — runs Caddy in a container
- **Markdown / HTML** — posts are plain files with YAML front matter

## Project structure

```
blog-lite/
├── compose.yaml            # Docker Compose config
├── publish.sh              # Script to publish drafts to site/posts/
├── template.md             # Starter template for new posts
├── caddy/
│   └── Caddyfile           # Caddy config
├── drafts/                 # Local drafts (not committed)
└── site/                   # Everything served to the web
    ├── index.html          # Dynamic homepage (lists all posts)
    ├── _post.html          # Template that wraps markdown posts
    ├── _htmlpost.html      # Template that wraps HTML posts
    ├── static/
    │   └── style.css
    └── posts/
        └── *.md / *.html   # Your content
```

## Local development

Requires Caddy installed locally. Start and stop the dev server with:

```bash
./server.sh --start
./server.sh --stop
```

The script rewrites the Caddyfile's `root` to point at your local `site/` folder so you can work without Docker.

## Production deployment

`compose.yaml` is for deploying to the production server. It expects an `APPDATA_PATH` environment variable pointing to the project root on the host. Deployment is handled separately from local dev.

## Writing a post

Posts are markdown or HTML files with a YAML front matter block at the top:

```markdown
---
title: My Post Title
date: 2026-06-24
summary: One sentence description shown on the homepage.
---

Content goes here.
```

Save drafts to the `drafts/` folder, then publish with:

```bash
./publish.sh                        # publish all drafts
./publish.sh drafts/my-post.md      # publish a specific file
./publish.sh -r /path/to/blog-lite  # specify a different project root
```

The publish script automatically escapes any `{{` and `}}` in your content so Caddy's template engine doesn't try to execute code examples as live templates.

## HTML posts

HTML files in `site/posts/` are supported. Use the same YAML front matter format — the front matter is stripped before rendering and the HTML body is wrapped in the standard site chrome.

## Deployment

The container maps `site/` as a read-only volume. Caddy re-evaluates templates on every request, so new posts appear immediately without a restart. A Caddyfile change requires:

```bash
docker compose restart
```
