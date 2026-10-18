;;; choicel.el --- Discover commands in your Emacs -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: help, convenience

;;; Commentary:
;; Run M-x choicel to find loaded commands and their current bindings.
;; Results open help; they never execute the recommended command.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'tabulated-list)

(defgroup choicel nil "Discover Emacs commands." :group 'help)

(defcustom choicel-max-results 30
  "Maximum number of search results."
  :type 'natnum)

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

(defvar-local choicel--source-buffer nil)
(defvar-local choicel--query nil)

(defcustom choicel-intent-hints
  '(("git\\|magit" . (magit-status vc-dir))
    ("ディレクトリ\\|フォルダ\\|directory\\|folder" . (dired dired-other-window)))
  "Preferred entry commands for common subjects in a query.
These are keyword hints, not semantic inference.  Commands must exist
in the collected index before they can be recommended."
  :type '(alist :key-type regexp :value-type (repeat symbol)))

(defun choicel--commands ()
  "Collect loaded commands and registered interactive autoloads.
Do not load packages merely to index their commands."
  (let (commands)
    (mapatoms
     (lambda (symbol)
       (when (commandp symbol)
         (let* ((definition (indirect-function symbol))
                (doc (if (autoloadp definition)
                         (let ((text (nth 2 definition)))
                           (and (stringp text) text))
                       (condition-case nil (documentation symbol t)
                         (error nil)))))
           (push (list symbol (or doc "")) commands)))))
    commands))

(defun choicel--terms (query)
  "Extract search terms from QUERY and expand Japanese hints."
  (let ((expanded (downcase query)))
    (dolist (pair choicel-synonyms)
      (when (string-match-p (regexp-quote (car pair)) query)
        (setq expanded (concat expanded " " (cdr pair)))))
    (delete-dups
     (cl-remove-if
      (lambda (word) (member word '("a" "an" "the" "to" "i" "want" "do" "how" "can" "please" "in")))
      (split-string expanded "[^[:alnum:]_-]+" t)))))

(defun choicel--bindings (command)
  "Return only currently effective keys for COMMAND in this buffer."
  (mapconcat #'key-description
             (cl-remove-if-not
              (lambda (key) (eq (key-binding key) command))
              (where-is-internal command nil nil nil))
             ", "))

(defun choicel--search (query commands)
  "Rank COMMANDS using keyword matches for QUERY in current buffer."
  (let ((terms (choicel--terms query)) results)
    (dolist (entry commands)
      (let* ((symbol (car entry))
             (name (symbol-name symbol))
             (doc (downcase (cadr entry)))
             (score 0))
        (dolist (hint choicel-intent-hints)
          (when (string-match-p (car hint) (downcase query))
            (let ((position (cl-position symbol (cdr hint))))
              (when position (cl-incf score (max 0 (- 100 (* 10 position))))))))
        (dolist (term terms)
          (let ((pattern (regexp-quote term)))
            (cond ((string-match-p pattern name) (cl-incf score 10))
                  ((string-match-p pattern doc) (cl-incf score 1)))))
        (when (> score 0)
          (let ((keys (choicel--bindings symbol)))
            (push (list symbol score keys
                        (car (split-string (cadr entry) "\n"))) results)))))
    (setq results
          (sort results
                (lambda (a b)
                  (if (= (nth 1 a) (nth 1 b))
                      (string-lessp (symbol-name (car a)) (symbol-name (car b)))
                    (> (nth 1 a) (nth 1 b))))))
    (cl-subseq results 0 (min (length results) choicel-max-results))))

(defun choicel-describe-command ()
  "Open help for the selected command."
  (interactive)
  (let ((command (tabulated-list-get-id)))
    (unless (and command (commandp command))
      (user-error "Select a command row first"))
    (describe-function command)))

(defun choicel-search-again ()
  "Search again using the original buffer's keymaps."
  (interactive)
  (unless (buffer-live-p choicel--source-buffer)
    (user-error "The original buffer has been closed; run M-x choicel in another buffer"))
  (let ((source choicel--source-buffer)
        (query (read-string "What do you want to do? " choicel--query)))
    (with-current-buffer source (choicel query))))

(defvar choicel-results-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map tabulated-list-mode-map)
    (define-key map (kbd "RET") #'choicel-describe-command)
    (define-key map (kbd "g") #'choicel-search-again)
    map))

(define-derived-mode choicel-results-mode tabulated-list-mode "Choicel"
  "Command search results.  RET opens help, g searches again, q quits."
  (setq tabulated-list-format [("Command" 36 t) ("Keys" 22 t) ("Description" 0 t)])
  (setq tabulated-list-padding 2)
  (tabulated-list-init-header))

;;;###autoload
(defun choicel (query)
  "Find commands matching QUERY without executing them.
Use the invoking buffer's active keymaps.  Include registered autoloads."
  (interactive (list (read-string "What do you want to do? ")))
  (when (string-empty-p (string-trim query)) (user-error "Enter a search phrase"))
  (let* ((source (current-buffer))
         (results (choicel--search query (choicel--commands)))
         (buffer (get-buffer-create "*choicel*")))
    (with-current-buffer buffer
      (choicel-results-mode)
      (setq choicel--source-buffer source
            choicel--query query
            header-line-format
            (format "Keyword search: %s | %d results | RET: help  g: search  q: quit"
                    query (length results))
            tabulated-list-entries
            (mapcar (lambda (row)
                      (list (car row)
                            (vector (symbol-name (car row))
                                    (if (string-empty-p (nth 2 row)) "—" (nth 2 row))
                                    (or (nth 3 row) ""))))
                    results))
      (tabulated-list-print t))
    (pop-to-buffer buffer)
    (unless results
      (message "No keyword matches. Try English terms such as split window or save file."))))

(provide 'choicel)
;;; choicel.el ends here
