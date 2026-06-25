#!/bin/bash

ROOT=.

if [ "$1" = "-r" ]; then
    ROOT=$2
    shift 2
fi

POSTS_DIR=$ROOT/site/posts
DRAFTS_DIR=$ROOT/drafts

has_front_matter() {
    head -1 "$1" | grep -q '^---$'
}

prompt_front_matter() {
    local file=$1
    echo "No front matter in $(basename "$file"). Enter post details:"

    read -rp "  Title: " title

    local today
    today=$(date '+%m.%d.%Y' | sed 's/\.0/\./g; s/^0//')
    read -rp "  Date [$today]: " date
    date=${date:-$today}

    read -rp "  Summary: " summary

    local tmp
    tmp=$(mktemp)
    printf -- '---\ntitle: %s\ndate: %s\nsummary: %s\n---\n' "$title" "$date" "$summary" | cat - "$file" > "$tmp"
    mv "$tmp" "$file"
}

publish() {
    local src=$1
    local dest=$POSTS_DIR/$(basename "$src")

    if ! has_front_matter "$src"; then
        prompt_front_matter "$src"
    fi

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
