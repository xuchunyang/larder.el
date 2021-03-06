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

(eval-when-compile
  (require 'cl-lib)
  (require 'let-alist))

;; It's fine even `auth-source' and `seq' is not loaded explicitly, because:
;; `url' -> `auth-source'
;; `json' -> `map' -> `seq'
;; However, it is better to load them explicitly.
(require 'auth-source)
(require 'json)
(require 'seq)
(require 'subr-x)                       ; `string-trim'
(require 'url)
(require 'wid-edit)

(defvar url-http-end-of-headers)
(defvar url-http-response-status)

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

(defun larder--auth-header ()
  (if larder-token
      (cons "Authorization"
            (format "Token %s"
                    (encode-coding-string larder-token 'utf-8)))
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
          (let ((url-request-extra-headers (list (larder--auth-header)))
                (url-show-status nil))
            (url-retrieve-synchronously url))
        (set-buffer-multibyte t)
        (goto-char url-http-end-of-headers)
        (let-alist (larder--json-read)
          (setq url .next)
          (setq results (nconc results .results)))))
    results))

(defun larder--post (url data)
  "Make a POST request to URL and return (status-code . content).

DATA is a alist."
  (with-current-buffer
      (let ((url-request-extra-headers
             (list (larder--auth-header)
                   (cons "Content-Type" "application/json")))
            (url-request-method "POST")
            (url-request-data (encode-coding-string
                               (json-encode-alist data)
                               'utf-8))
            (url-show-status nil))
        (url-retrieve-synchronously url))
    (set-buffer-multibyte t)
    (goto-char url-http-end-of-headers)
    (cons url-http-response-status (larder--json-read))))

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
  (let ((total (apply #'+ (mapcar (lambda (x) (let-alist x .links)) larder--folders)))
        (downloaded 0))
    (dolist (folder larder--folders)
      (let-alist folder
        (unless (assoc folder larder--bookmarks)
          (message (concat "[%" (number-to-string (length (format "%s" total))) "d/%d] Fetching bookmarks...")
                   downloaded total)
          (push (cons folder (larder--bookmarks .id)) larder--bookmarks))
        (cl-incf downloaded (length (assoc-default folder larder--bookmarks)))))))

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
(declare-function helm-make-source "helm-source" (name class &rest args))
(declare-function helm-make-actions "helm-lib" (&rest args))
(declare-function helm-marked-candidates "helm" (&rest args))

;;;###autoload
(defun larder-helm ()
  (interactive)
  (larder--cache)
  (require 'helm)
  (helm :sources
        (helm-make-source "Larder Search" 'helm-source-sync
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
                         (browse-url .url))))
                   "EWW"
                   (lambda (_candidate)
                     (dolist (bookmark (helm-marked-candidates))
                       (let-alist bookmark
                         (eww .url))))
                   "Copy URL"
                   (lambda (_candidate)
                     (let ((urls (mapconcat (lambda (bookmark)
                                              (alist-get 'url bookmark))
                                            (helm-marked-candidates)
                                            "\n")))
                       (kill-new urls)
                       (message "Copied: %s" urls)
                       urls)))
          :multiline t)))

(defvar eww-data)

;; TODO: Verify input in time or switch to (info "(widget) Top")
(defun larder--add-bookmark-read-args ()
  (let ((title (string-trim
                (read-string "Title: " (and (bound-and-true-p eww-data)
                                            (plist-get eww-data :title)))))
        (url (string-trim
              (read-string "URL: " (and (bound-and-true-p eww-data)
                                        (plist-get eww-data :url)))))
        (parent (progn
                  (unless larder--folders
                    (setq larder--folders (larder--folders)))
                  (let ((name (let ((completion-ignore-case t))
                                (completing-read "Folder: "
                                                 ;; FIXME name maybe not unique, use path instead
                                                 (cl-loop for f in larder--folders
                                                          collect (alist-get 'name f))
                                                 nil t
                                                 (cl-loop for f in larder--folders
                                                          return (alist-get 'name f))))))
                    (cl-loop for f in larder--folders
                             when (string= name (alist-get 'name f))
                             return (alist-get 'id f)))))
        (tag (vconcat (split-string (read-string "Tags (Optional, separated by spaces): "))))
        (description (string-trim (read-string "Description (Optional): "))))
    (and (string-empty-p title) (setq title nil))
    (and (string-empty-p url) (setq url nil))
    (and (string-empty-p parent) (setq parent nil))
    (and (string-empty-p description) (setq description nil))
    (list title url parent tag description)))

;;;###autoload
(defun larder-add-bookmark (title url parent tags description)
  (interactive (larder--add-bookmark-read-args))
  (unless url
    (user-error "URL cannot be empty"))
  (unless parent
    (user-error "Parent cannot be empty"))
  (pcase (larder--post "https://larder.io/api/1/@me/links/add/"
                       `(,@(and title `((title  . ,title)))
                         (url    . ,url)
                         (parent . ,parent)
                         (tags   . ,tags)
                         ,@(and description `((description . ,description)))))
    (`(201 . ,alist)
     (message "Bookmark '%s' add successfully" (alist-get 'title alist)))
    (`(,code . ,alist)
     (message "Error (%d): %S"
              code
              ;; The documentation says there is an `error' field, but it is not
              ;; always true, for example, when I send {"tags": "null"}, it responses:
              ;; {"tags":["This field may not be null."]}
              (or (alist-get 'error alist) alist)))))

;;;###autoload
(defun larder-add-bookmark-widget ()
  (interactive)
  (unless larder--folders
    (setq larder--folders (larder--folders)))
  (let ((folders (mapcar (lambda (x) (alist-get 'name x)) larder--folders))
        url-widget
        title-widget
        tags-widget
        description-widget
        folder-widget)
    (unless (equal folders (seq-uniq folders))
      (error "Can't handle multiple folders with the same name"))

    (switch-to-buffer "*Larder Add Bookmark**")
    (kill-all-local-variables)
    (let ((inhibit-read-only t))
      (erase-buffer))
    (remove-overlays)

    (setq url-widget
          (widget-create 'editable-field :format "URL:         %v\n" :size 50 :valid-regexp (rx bos (or "http" "https") "://")))
    (setq title-widget
          (widget-create 'editable-field :format "Title:       %v\n" :size 50))
    (setq tags-widget
          (widget-create 'editable-field :format "Tags:        %v\n" :size 50))
    (setq description-widget
          (widget-create 'editable-field :format "Description: %v\n" :size 50))
    
    (widget-insert "Folder:\n")
    (setq folder-widget
          (apply #'widget-create 'radio-button-choice
                 :value (car folders)
                 (mapcar (lambda (x) `(item ,x)) folders)))
    (widget-insert "\n")
    
    (widget-create 'push-button
                   :notify (lambda (&rest _)
                             (when (widget-field-validate url-widget)
                               (user-error "Invalid URL: '%s'" (widget-value url-widget)))
                             (let* ((folder (widget-value folder-widget))
                                    (parent (cl-loop for x in larder--folders
                                                     when (string= folder (alist-get 'name x))
                                                     return (alist-get 'id x)))
                                    (url (string-trim (widget-value url-widget)))
                                    (title (string-trim (widget-value title-widget)))
                                    (tags (vconcat (split-string (widget-value tags-widget))))
                                    (description (string-trim (widget-value description-widget))))
                               (when (string-empty-p title) (setq title nil))
                               (when (string-empty-p description) (setq description nil))
                               (larder-add-bookmark title url parent tags description)))
                   "Add Bookmark")
    (widget-insert " ")
    (widget-create 'push-button
                   :notify (lambda (&rest _)
                             (larder-add-bookmark-widget))
                   "Reset Form")
    (widget-insert "\n")
    (use-local-map widget-keymap)
    (widget-setup)
    (goto-char (point-min))
    (widget-forward 1)))

(provide 'larder)
;;; larder.el ends here
