---
title: Self-Hosted Research Blog with Caddy
date: 4.24.2026
summary: A guide to standing up a barebones static blog on FlopTower that auto-updates its homepage whenever you drop a new post into the content folder. No database, no CMS, no build step — just files and one config.
---
---

## Part 1: How Caddy works (the 5-minute version)

Caddy is an HTTP server written in Go, in the same family as nginx and Apache but with a very different philosophy:

- **Single binary, no modules to install.** Everything you need is compiled in. You run one program and it serves files.
- **Automatic HTTPS.** If you give it a public domain, it gets a Let's Encrypt cert and renews it. (You won't use this since you're going through a Cloudflare tunnel, but it's worth knowing.)
- **Human-readable config.** The `Caddyfile` format is like nginx's config except actually pleasant. Compare:

  **nginx:**
  ```nginx
  server {
      listen 80;
      server_name example.com;
      root /var/www;
      location / {
          try_files $uri $uri/ =404;
      }
  }
  ```

  **Caddyfile:**
  ```caddyfile
  example.com {
      root * /var/www
      file_server
  }
  ```

- **Directive-based.** Each line is a directive (`file_server`, `reverse_proxy`, `templates`, etc.) with optional arguments. Caddy sorts them into the correct handler order for you — so you don't need to worry about whether `try_files` comes before `rewrite`.
- **Templates are built in.** This is the part that matters for us. Caddy has a `templates` directive that runs Go's `text/template` engine on HTML responses before sending them. That's how we get a dynamic index page without any build step or external CMS.

### The conceptual model

A Caddy site block has three jobs:

1. **Match the request.** By hostname (`research.asay.dev`), path, method, whatever.
2. **Transform it.** Rewrites, redirects, header changes.
3. **Respond.** Serve a file, reverse-proxy it, return a template, etc.

Our setup will do exactly this: match any request, rewrite markdown requests to a template, and serve everything else as static files.

---

## Part 2: Architecture

Here's the whole project on disk:

```
/mnt/user/appdata/research/
├── docker-compose.yml          # defines the Caddy container
├── Caddyfile                   # Caddy's config
└── site/                       # everything served to the web lives here
    ├── index.html              # the dynamic homepage (a template)
    ├── _post.html              # template that renders individual posts
    ├── static/
    │   └── style.css           # site-wide stylesheet
    └── posts/
        ├── 2026-04-24-how-llms-think.md
        └── 2026-04-20-tool-use-patterns.md
```

**What each piece does:**

| File | Role |
|------|------|
| `docker-compose.yml` | Tells Docker to run Caddy, mount the config and site folder |
| `Caddyfile` | Tells Caddy *how* to serve things — static files, which paths get the template treatment, etc. |
| `site/index.html` | The homepage template. Every time it's requested, Caddy rebuilds the post list by scanning `posts/` |
| `site/_post.html` | A wrapper that takes a markdown file and renders it as a full HTML page |
| `site/posts/*.md` | Your actual content. One markdown file per post, with YAML front matter at the top |

**Content format:** posts are markdown files with a small YAML header. Markdown allows raw HTML inline, so when Claude generates one of those "nice HTML pages" you can paste the whole thing in below the front matter and it'll render fine. You get the best of both: simple posts stay simple, fancy ones can be arbitrarily rich.

**Filename convention:** `YYYY-MM-DD-slug.md`. The date prefix means files sort chronologically on disk, which we can use for the index order.

---

## Part 3: The Caddyfile

Create `/mnt/user/appdata/research/Caddyfile`:

```caddyfile
:80 {
    root * /srv
    encode gzip

    # Let markdown files be requested without the .md extension
    # e.g. /posts/how-llms-think → /posts/how-llms-think.md
    try_files {path} {path}.md

    # Any request ending in .md gets rewritten to the post template
    # (the template reads the original path to know which file to render)
    @markdown path *.md
    rewrite @markdown /_post.html

    # Enable template processing on HTML responses
    templates

    # Serve everything else as a static file
    file_server
}
```

**What each directive does:**

- `:80` — listen on port 80 inside the container (Cloudflare tunnel handles HTTPS from outside)
- `root * /srv` — the document root. `*` means "for all requests." We'll mount our `site/` folder to `/srv` in the container.
- `encode gzip` — gzip responses on the fly. Free bandwidth savings.
- `try_files {path} {path}.md` — if `/posts/foo` doesn't exist, try `/posts/foo.md`. Gives us clean URLs without the `.md` extension.
- `@markdown path *.md` — a **named matcher**. This defines a reusable filter for "any request whose path ends in `.md`."
- `rewrite @markdown /_post.html` — for matched requests, swap the URL to `/_post.html`. The template inside will read the *original* URL to figure out which markdown file to load.
- `templates` — process HTML responses through Caddy's template engine. Without this directive, `{{ "{{" }}...{{ "}}" }}` syntax in HTML files gets served as literal text.
- `file_server` — if none of the above produced a response, serve the requested file from disk.

Caddy automatically sorts directives into the correct order, so you don't have to think about it. The visual order in the file is fine.

---

## Part 4: The dynamic index template

This is the interesting part. Create `/mnt/user/appdata/research/site/index.html`:

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Research — asay.dev</title>
    <link rel="stylesheet" href="/static/style.css">
</head>
<body>
    <header>
        <h1>Research Notes</h1>
        <p class="tagline">Experiments, explorations, and things I learned along the way.</p>
    </header>

    <main>
        <ul class="post-list">
            {{ "{{" }}- $posts := listFiles "/posts" -{{ "}}" }}
            {{ "{{" }}- $count := len $posts -{{ "}}" }}
            {{ "{{" }}- range $i, $_ := $posts -{{ "}}" }}
                {{ "{{" }}- /* iterate in reverse so newest-first */ -{{ "}}" }}
                {{ "{{" }}- $file := index $posts (sub (sub $count 1) $i) -{{ "}}" }}
                {{ "{{" }}- if not $file.IsDir -{{ "}}" }}
                    {{ "{{" }}- $raw := include (printf "/posts/%s" $file.Name) -{{ "}}" }}
                    {{ "{{" }}- $parsed := splitFrontMatter $raw -{{ "}}" }}
                    {{ "{{" }}- $slug := trimSuffix ".md" $file.Name -{{ "}}" }}
                    <li class="post-item">
                        <a href="/posts/{{ "{{" }} $slug {{ "}}" }}">
                            <time datetime="{{ "{{" }} $parsed.Meta.date {{ "}}" }}">{{ "{{" }} $parsed.Meta.date {{ "}}" }}</time>
                            <h2>{{ "{{" }} $parsed.Meta.title {{ "}}" }}</h2>
                            {{ "{{" }}- with $parsed.Meta.summary -{{ "}}" }}
                                <p class="summary">{{ "{{" }} . {{ "}}" }}</p>
                            {{ "{{" }}- end -{{ "}}" }}
                        </a>
                    </li>
                {{ "{{" }}- end -{{ "}}" }}
            {{ "{{" }}- end -{{ "}}" }}
        </ul>
    </main>

    <footer>
        <p>Hosted on FlopTower. Last rebuilt on request.</p>
    </footer>
</body>
</html>
```

**Template walkthrough:**

- `{{ "{{" }} $posts := listFiles "/posts" {{ "}}" }}` — call Caddy's built-in `listFiles` function on the `posts/` directory (relative to the site root `/srv`). Returns a slice of file-info objects. Assign it to the variable `$posts`.
- `{{ "{{" }} $count := len $posts {{ "}}" }}` — number of files.
- `{{ "{{" }} range $i, $_ := $posts {{ "}}" }}` — iterate. `$i` is the index, `$_` is the value (which we ignore because we're going to pull the file by reverse index).
- `{{ "{{" }} $file := index $posts (sub (sub $count 1) $i) {{ "}}" }}` — grab the file at index `(count - 1 - i)`, i.e. iterate backwards so the newest file comes first. This is a slightly awkward dance because Caddy's template funcs don't include a `reverse`. You only have to understand this one line once.
- `{{ "{{" }} if not $file.IsDir {{ "}}" }}` — skip subdirectories (in case you add any).
- `{{ "{{" }} $raw := include (printf "/posts/%s" $file.Name) {{ "}}" }}` — read the file's contents into `$raw`.
- `{{ "{{" }} $parsed := splitFrontMatter $raw {{ "}}" }}` — split the YAML front matter from the body. Now `$parsed.Meta.title`, `$parsed.Meta.date` etc. are accessible.
- `{{ "{{" }} $slug := trimSuffix ".md" $file.Name {{ "}}" }}` — strip the `.md` so the link is clean.
- The rest is normal HTML with template variable substitution.

Every time someone hits the homepage, Caddy runs this template fresh. Drop a new markdown file into `posts/` and it appears immediately — no restart, no build.

---

## Part 5: The post template

This renders an individual markdown post as a full HTML page. Create `/mnt/user/appdata/research/site/_post.html`:

```html
{{ "{{" }}- $md := include .OriginalReq.URL.Path | splitFrontMatter -{{ "}}" }}
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{ "{{" }} $md.Meta.title {{ "}}" }} — asay.dev</title>
    <link rel="stylesheet" href="/static/style.css">
</head>
<body>
    <header>
        <a href="/" class="back">← All posts</a>
    </header>
    <article>
        <h1>{{ "{{" }} $md.Meta.title {{ "}}" }}</h1>
        <time datetime="{{ "{{" }} $md.Meta.date {{ "}}" }}">{{ "{{" }} $md.Meta.date {{ "}}" }}</time>
        <div class="content">
            {{ "{{" }} markdown $md.Body {{ "}}" }}
        </div>
    </article>
</body>
</html>
```

**How this works:**

- `.OriginalReq.URL.Path` — the path the user *originally* requested, before Caddy's rewrite sent them to `/_post.html`. So if they asked for `/posts/how-llms-think.md`, that's what we get here.
- `include ...` — read the markdown file.
- `splitFrontMatter` — peel off the YAML header.
- `{{ "{{" }} markdown $md.Body {{ "}}" }}` — render the markdown body to HTML. (If the body is already raw HTML, it passes through unchanged — markdown is a superset.)

---

## Part 6: Writing a post

A post is a markdown file with YAML front matter:

```markdown
---
title: How LLMs Think About Their Own Thinking
date: 2026-04-24
summary: An experiment in probing model introspection using tool calls and structured output.
---

# Introduction

I've been curious about whether LLMs can meaningfully report on their own
reasoning processes. This post walks through...

## The Setup

...content here, can include **markdown**, inline `code`, or raw HTML...

<div class="custom-widget">
  Even fancy HTML works fine because markdown allows raw HTML.
</div>
```

Save it as `/mnt/user/appdata/research/site/posts/2026-04-24-how-llms-think.md`. It shows up on the homepage on the next page load.

**When Claude gives you a complete HTML artifact** (like the one you mentioned), the workflow is even simpler: open a new markdown file, paste the front matter block, then paste the whole HTML below. Save, done.

---

## Part 7: The stylesheet

Minimal starter at `/mnt/user/appdata/research/site/static/style.css`:

```css
:root {
    --bg: #0f0f0f;
    --fg: #e8e8e8;
    --muted: #888;
    --accent: #7aa7ff;
    --border: #2a2a2a;
}

* { box-sizing: border-box; }

body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    max-width: 720px;
    margin: 0 auto;
    padding: 2rem 1.5rem 4rem;
    background: var(--bg);
    color: var(--fg);
    line-height: 1.6;
}

header h1 { margin-bottom: 0.25rem; }
.tagline { color: var(--muted); margin-top: 0; }

.post-list {
    list-style: none;
    padding: 0;
    margin: 2rem 0;
}

.post-item {
    border-bottom: 1px solid var(--border);
    padding: 1.25rem 0;
}

.post-item a {
    color: inherit;
    text-decoration: none;
    display: block;
}

.post-item a:hover h2 { color: var(--accent); }

.post-item time {
    color: var(--muted);
    font-size: 0.85rem;
    font-variant-numeric: tabular-nums;
}

.post-item h2 {
    margin: 0.25rem 0;
    font-size: 1.25rem;
    font-weight: 600;
    transition: color 0.15s;
}

.summary { color: var(--muted); margin: 0.25rem 0 0; }

article h1 { margin-bottom: 0.25rem; }
article > time { color: var(--muted); }
article .content { margin-top: 2rem; }
article pre {
    background: #1a1a1a;
    padding: 1rem;
    border-radius: 6px;
    overflow-x: auto;
}
article code {
    background: #1a1a1a;
    padding: 0.1em 0.35em;
    border-radius: 3px;
    font-size: 0.9em;
}
article pre code { background: transparent; padding: 0; }

.back { color: var(--muted); text-decoration: none; font-size: 0.9rem; }
.back:hover { color: var(--accent); }

footer { margin-top: 4rem; color: var(--muted); font-size: 0.85rem; }
```

Adjust to taste. This is just a starting point.

---

## Part 8: Docker Compose

Create `/mnt/user/appdata/research/docker-compose.yml`:

```yaml
services:
  caddy:
    image: caddy:2-alpine
    container_name: research-blog
    restart: unless-stopped
    ports:
      - "8088:80"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./site:/srv:ro
      - caddy_data:/data
      - caddy_config:/config
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost/"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

volumes:
  caddy_data:
  caddy_config:
```

**Notes:**

- `caddy:2-alpine` — small image (~50 MB), includes everything we need. The `2-alpine` tag pins to Caddy v2 on Alpine Linux.
- Host port `8088` is arbitrary — pick whatever's free on FlopTower. This is the port your Cloudflare tunnel will point at.
- The `site/` folder is mounted **read-only** (`:ro`). Caddy doesn't need to write to it, and read-only mounts prevent accidents.
- `caddy_data` and `caddy_config` are named volumes. Caddy uses them for TLS state and runtime config. Since you're behind a tunnel and not doing TLS, they'll stay mostly empty, but Caddy expects them.
- The healthcheck follows the same pattern you've been using on your other stacks.

Deploy it through Dockhand like any other stack.

---

## Part 9: Hooking it up to Cloudflare

In the Cloudflare Zero Trust dashboard, edit your tunnel and add a public hostname:

- **Subdomain:** `research` (or whatever you like)
- **Domain:** `asay.dev`
- **Service type:** `HTTP`
- **URL:** `floptower:8088` (or whatever Tailscale/LAN name resolves to your host on the port you picked above)

Cloudflare handles the TLS cert automatically through their edge. That's why we don't bother with HTTPS inside Caddy.

If you want to keep it Tailscale-only instead (more in line with how you run the admin-y stuff), just point a Tailscale serve config at `http://localhost:8088` and skip the tunnel.

---

## Part 10: The workflow, end to end

1. You do some research, chat with Claude, Claude produces something interesting.
2. You open a new file: `site/posts/2026-04-24-whatever.md`.
3. You add the YAML front matter block (title, date, summary).
4. You paste the content below the front matter (markdown, HTML, or a mix).
5. You save. The homepage now shows the new post on next refresh.
6. That's the entire deploy process.

No git push, no build, no cache to bust, no CMS login. The server is genuinely serving files off disk in real time.

---

## Part 11: Where to go from here

Things you might want to add eventually, roughly in ascending complexity:

- **RSS feed.** Same template pattern — one more template file at `/feed.xml` that iterates `listFiles` and outputs RSS XML. Means anyone (including you) can follow the blog from an RSS reader.
- **Syntax highlighting for code blocks.** Caddy's `markdown` function uses Goldmark under the hood and supports Chroma highlighting. Needs a `chroma.css` include and a config tweak.
- **Tags.** Add `tags: [llms, tooling]` to front matter, then a tag-filter page that lists posts matching a tag.
- **Drafts.** Add `draft: true` to front matter, skip in the index template with an `if` check.
- **Search.** Client-side search over a JSON index file you generate from the posts. A small sidecar container could rebuild the index on file change via inotify, but honestly for a personal blog, Ctrl-F on the homepage is fine until it isn't.
- **View counts / analytics.** Plausible or Umami self-hosted. Probably not worth it for a research journal, but it's an option.
- **Migrating later.** Every post is a plain markdown file with standard YAML front matter. Moving to Hugo, Astro, or Ghost later is a copy-paste job. You won't be locked in.

---

## Appendix: quick sanity-check checklist

Once the stack is up, verify each piece:

1. `docker logs research-blog` → should show `serving initial configuration` and no errors
2. Curl from inside FlopTower: `curl http://localhost:8088/` → should return your index HTML with the post list
3. Add a test markdown file, refresh — does it appear in the list?
4. Click through to a post — does it render with the markdown converted?
5. Hit the tunnel URL from outside — does it load over HTTPS?
6. Check `docker logs research-blog` again — any 404s or template errors?

If the template throws an error (usually a missing function or a typo), Caddy will log it and serve the raw template text with the error visible. That's normal and makes debugging easy.
