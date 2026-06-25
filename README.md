# BlogLite

A minimal self-hosted blog engine. No database, no build step, no CMS — just markdown and HTML files served dynamically by Caddy. Drop a file in `site/posts/`, it appears on the homepage on the next page load.

## Stack

- **Caddy** — HTTP server with a built-in Go template engine
- **Docker** — runs Caddy in a container on the production server
- **Markdown / HTML** — posts are plain files with YAML front matter

## Project structure

```
blog-lite/
├── Caddyfile               # Caddy config
├── compose.yaml            # Docker Compose config (production)
├── server.sh               # Local dev server (start/stop)
├── publish.sh              # Script to publish drafts to site/posts/
├── template.md             # Starter template for new posts
├── drafts/                 # Local drafts (not committed)
└── site/                   # Everything served to the web
    ├── index.html          # Dynamic homepage (lists all posts)
    ├── _post.html          # Template wrapper for markdown posts
    ├── _htmlpost.html      # Injects back button into HTML posts
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

`compose.yaml` is for deploying to the production server. It expects an `APPDATA_PATH` environment variable pointing to the project root on the host (with a trailing slash). Caddy data and config are stored in named Docker volumes.

## Writing a post

Posts are markdown or HTML files with a YAML front matter block at the top:

```markdown
---
title: My Post Title
date: 6.24.2026
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

If a draft has no front matter, the publish script will prompt you for the title, date, and summary before publishing.

The publish script also escapes any `{{` and `}}` in your content so Caddy's template engine doesn't treat code examples as live templates.

## HTML posts

HTML files in `site/posts/` are fully supported. The post renders exactly as written — its own `<head>`, styles, and layout are preserved. The only additions are:

- YAML front matter is stripped before rendering
- A fixed "← All posts" back link is injected at the top of `<body>`

## Caddyfile change

The container mounts `Caddyfile` read-only. A config change requires:

```bash
docker compose restart
```

Caddy re-evaluates templates on every request, so new posts appear immediately without a restart.
