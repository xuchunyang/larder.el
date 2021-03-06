# An Emacs client for [Larder: bookmarking for developers.](https://larder.io/)

[![Build Status](https://travis-ci.org/xuchunyang/larder.el.svg?branch=master)](https://travis-ci.org/xuchunyang/larder.el) (Green means byte compiling without errors/warnings, I have not written any tests)

## Requires

- Emacs 25.1 or later

## Setup

Visit https://larder.io/apps/clients/ to get your API token, add the follwing to your `.authinfo` or `.authinfo.gpg`:

    machine larder.io password YOUR_API_TOKEN

## Usage

### `M-x larder-org`

List bookmarks in Org mode.

### `M-x larder-list-bookmarks`

List bookmarks in the boring Tabulated List mode.

### `M-x larder-helm`

Search bookmarks using Helm.

### `larder-add-bookmark`

Add a bookmark via the Minibuffer.

### `M-x larder-add-bookmark-widget`

Add a bookmark via the Widget.

![Screenshot of M-x larder-add-bookmark-widget](screenshots/larder-add-bookmark-widget-2019-05-20.png)

## Features / To-do list

- [x] List Bookmarks
- [x] Search bookmarks using the similiar syntax at https://larder.io/home/f/all/all/
- [ ] Add/Delete/Edit a bookmark
