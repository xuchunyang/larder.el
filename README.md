# An Emacs client for [Larder: bookmarking for developers.](https://larder.io/)

[![Build Status](https://travis-ci.org/xuchunyang/larder.el.svg?branch=master)](https://travis-ci.org/xuchunyang/larder.el) (Green means byte compiling without errors/warnings, I have not written any tests)

## Requires

- Emacs 25.1 or later

## Setup

Visit https://larder.io/apps/clients/ to get your API token, add the follwing to your `.authinfo` or `.authinfo.gpg`:

    machine larder.io password YOUR_API_TOKEN

## Usage

### `M-x larder-org`

List your bookmarks in Org mode.

### `M-x larder-list-bookmarks`

List your bookmarks in the boring Tabulated List mode.

## Features / To-do list

- [x] List Bookmarks
- [ ] Add/Delete/Edit a bookmark
