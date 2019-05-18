;;; larder.el --- Access your bookmarks from Larder  -*- lexical-binding: t; -*-

;; Copyright (C) 2019  徐春阳

;; Author: 徐春阳 <mail@xuchunyang.me>
;; Homepage: https://github.com/xuchunyang/larder.el
;; Created: 己亥年 己巳月 癸丑日
;; Package-Requires: ((emacs "25.1"))
;; Version: 0

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; An Emacs client for Larder <https://larder.io/>.

;;; Code:

(eval-when-compile (require 'let-alist))

(require 'json)
(require 'url)

(defvar url-http-end-of-headers)

(defgroup larder nil
  "An Emacs client for Larder <https://larder.io/>."
  :group 'external)

(defun larder--auth-source-get-token ()
  (let ((plist (car (auth-source-search :max 1 :host "larder.io"))))
    (let ((v (plist-get plist :secret)))
      (if (functionp v) (funcall v) v))))

(defcustom larder-token (larder--auth-source-get-token)
  "Visit URL `https://larder.io/apps/clients/' to get your token."
  :type 'string)

(defun larder--request-headers ()
  (if larder-token
      (list (cons "Authorization" (format "Token %s" larder-token)))
    (user-error "`larder-token' is not set")))

(defun larder--json-read ()
  (let ((json-object-type 'alist)
        (json-array-type  'list)
        (json-key-type    'symbol)
        (json-false       nil)
        (json-null        nil))
    (json-read)))

(defun larder--get (url)
  (let (results)
    (while url
      (with-current-buffer
          (let ((url-request-extra-headers (larder--request-headers)))
            (url-retrieve-synchronously url))
        (set-buffer-multibyte t)
        (goto-char url-http-end-of-headers)
        (let-alist (larder--json-read)
          (setq url .next)
          (setq results (nconc results .results)))))
    results))

(defun larder--folders ()
  (larder--get "https://larder.io/api/1/@me/folders/"))

(defun larder--bookmarks (id)
  ;; Requests are rate limited to 600 requests/hour/user which you probably
  ;; won’t ever even notice
  ;;
  ;; (/ 1000 20) => 50
  ;; (/ 1000 50) => 20
  (larder--get (format "https://larder.io/api/1/@me/folders/%s/?limit=50" id)))

(defun larder--folders-tree (folders)
  "Convert a list of FOLDERS into tree."
  (let ((tree (cons '((name . "/")) ()))
        (rest (reverse folders))
        (done ()))
    (cl-labels ((walk (tree new-folder)
                      (when (equal (alist-get 'id (car tree))
                                   (alist-get 'parent new-folder))
                        (push (list new-folder) (cdr tree))
                        (push new-folder done)
                        (throw 'found t))
                      (dolist (x (cdr tree))
                        (walk x new-folder))))
      (while rest
        (dolist (folder rest)
          (catch 'found
            (walk tree folder)))
        (setq rest (seq-difference rest done)))
      tree)))

(defvar larder--folders nil
  "A list of folders.")
(defvar larder--bookmarks nil
  "A list of (Folder . Bookmarks).")

(defun larder--cache ()
  (unless larder--folders
    (setq larder--folders (larder--folders)))
  (let ((idx 1))
    (dolist (folder larder--folders)
      (unless (assoc folder larder--bookmarks)
        (let-alist folder
          (push (cons folder (larder--bookmarks .id)) larder--bookmarks)
          (message "[%d/%d] Fetching bookmarks in %s..." idx (length larder--folders) .name)))
      (setq idx (1+ idx)))))

(declare-function org-make-link-string "org" (link &optional description))

;;;###autoload
(defun larder-org ()
  "List bookmarks using Org mode."
  (interactive)
  (larder--cache)
  (cl-labels ((print-tree
               (tree level)
               (when (> level 0)
                 (insert (format "%s %s\n" (make-string level ?*) (alist-get 'name (car tree))))
                 (dolist (bookmark (assoc-default (car tree) larder--bookmarks))
                   (let-alist bookmark
                     (insert (format "%s %s%s\n"
                                     (make-string (1+ level) ?*)
                                     (org-make-link-string .url .title)
                                     (if .tags
                                         (format " :%s:" (mapconcat (lambda (tag) (alist-get 'name tag)) .tags ":"))
                                       "")))
                     (when .description
                       (insert .description "\n")))))
               (dolist (x (cdr tree))
                 (print-tree x (1+ level)))))
    (with-current-buffer (get-buffer-create "*Larder Org*")
      (display-buffer (current-buffer))
      (erase-buffer)
      (org-mode)
      (print-tree (larder--folders-tree larder--folders) 0))))

(define-derived-mode larder-list-mode tabulated-list-mode "Larder Bookmark"
  "Major mode for browsing a list of packages."
  (setq tabulated-list-format
        [("Title" 90 t nil)
         ("URL"   30 t nil)])
  (tabulated-list-init-header))

;;;###autoload
(defun larder-list-bookmarks ()
  "Display a list of bookmarks."
  (interactive)
  (larder--cache)
  (set-buffer (pop-to-buffer "*Larder Bookmarks*"))
  (larder-list-mode)
  (setq tabulated-list-entries
        (let (result)
          (pcase-dolist (`(,_ . ,bookmarks) larder--bookmarks)
            (dolist (bookmark bookmarks)
              (let-alist bookmark
                (push (list .id (vector .title
                                        (cons (replace-regexp-in-string (rx bos "http" (opt "s") "://") "" .url)
                                              (list 'action (lambda (_) (browse-url .url))))))
                      result))))
          (nreverse result)))
  (tabulated-list-print))

(declare-function helm "helm" (&rest plist))
(declare-function helm-build-sync-source "helm-source" (name &rest args))
(declare-function helm-make-actions "helm-lib" (&rest args))
(declare-function helm-marked-candidates "helm" (&rest args))

;;;###autoload
(defun larder-helm ()
  (interactive)
  (larder--cache)
  (helm :sources
        (helm-build-sync-source "Larder Search"
          :candidates
          (let (candidates)
            (pcase-dolist (`(,_ . ,bookmarks) larder--bookmarks)
              (dolist (bookmark bookmarks)
                (let-alist bookmark
                  (push (cons (mapconcat
                               #'identity
                               (delq nil
                                     (list .title
                                           .description
                                           (and .tags
                                                (mapconcat
                                                 (lambda (tag)
                                                   (concat "#" (alist-get 'name tag)))
                                                 .tags " "))))
                               "\n")
                              bookmark)
                        candidates))))
            (nreverse candidates))
          :action (helm-make-actions
                   "Browse URL"
                   (lambda (_candidate)
                     (dolist (bookmark (helm-marked-candidates))
                       (let-alist bookmark
                         (browse-url .url)))))
          :multiline t)))

(provide 'larder)
;;; larder.el ends here
