#!/bin/bash

ROOT=.

if [ "$1" = "-r" ]; then
    ROOT=$2
    shift 2
fi

POSTS_DIR=$ROOT/site/posts
DRAFTS_DIR=$ROOT/drafts

publish() {
    local src=$1
    local dest=$POSTS_DIR/$(basename "$src")
    sed 's/{{/__LBRACE__/g; s/}}/{{ "}}" }}/g; s/__LBRACE__/{{ "{{" }}/g' "$src" > "$dest" && rm "$src"
    echo "Published: $(basename "$src")"
}

if [ -n "$1" ]; then
    if [ ! -f "$1" ]; then
        echo "File not found: $1"
        exit 1
    fi
    publish "$1"
else
    for f in "$DRAFTS_DIR"/*.md "$DRAFTS_DIR"/*.html; do
        [ -f "$f" ] && publish "$f"
    done
fi
