;;; choicel-dictionary.el --- Keyword hints for choicel -*- lexical-binding: t; -*-

;;; Commentary:
;; Edit the synonym and command preference lists here, then eval-buffer.
;; Entries are keyword hints; they do not execute commands.

;;; Code:

(defgroup choicel nil "Discover Emacs commands." :group 'help)

(defcustom choicel-synonyms
  '(("ウィンドウ" . "window") ("左右" . "right")
    ("上下" . "below") ("分割" . "split") ("バッファ" . "buffer")
    ("ファイル" . "file") ("開" . "find open") ("保存" . "save")
    ("ディレクトリ" . "directory dired") ("フォルダ" . "directory dired")
    ("一覧" . "list") ("git" . "git magit vc")
    ("移動" . "move rename") ("削除" . "delete")
    ("検索" . "search") ("置換" . "replace") ("元に戻" . "undo")
    ("コピー" . "copy") ("貼り付け" . "yank")
    ("切り替" . "switch") ("閉じ" . "kill delete"))
  "Small Japanese hints for keyword search, not semantic translation."
  :type '(alist :key-type string :value-type string))

(defcustom choicel-intent-hints
  '(("git\\|magit" . (magit-status vc-dir))
    ("ディレクトリ\\|フォルダ\\|directory\\|folder" . (dired dired-other-window)))
  "Preferred entry commands for common subjects in a query.
These are keyword hints, not semantic inference.  Commands must exist
in the collected index before they can be recommended."
  :type '(alist :key-type regexp :value-type (repeat symbol)))

(provide 'choicel-dictionary)
;;; choicel-dictionary.el ends here
