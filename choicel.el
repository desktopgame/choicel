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

(require 'choicel-dictionary)
(require 'choicel-systemone)

(defcustom choicel-max-results 30
  "Maximum number of search results."
  :group 'choicel
  :type 'natnum)

(defvar-local choicel--source-buffer nil)
(defvar-local choicel--query nil)
(defvar-local choicel--cancel-search nil)
(defvar-local choicel--search-token nil)

(defun choicel--cancel-pending ()
  "Cancel work belonging to this results buffer."
  (when choicel--cancel-search (funcall choicel--cancel-search))
  (setq choicel--cancel-search nil choicel--search-token nil))

(defun choicel-cancel-search ()
  "Cancel System One search and keep the current keyword results."
  (interactive)
  (choicel--cancel-pending)
  (setq header-line-format "System One cancelled | Keyword results | g: search  q: quit"))

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
    (define-key map (kbd "C-c C-k") #'choicel-cancel-search)
    (define-key map (kbd "g") #'choicel-search-again)
    map))

(define-derived-mode choicel-results-mode tabulated-list-mode "Choicel"
  "Command search results.  RET opens help, g searches again, q quits."
  (setq tabulated-list-format [("Command" 36 t) ("Keys" 22 t) ("Description" 0 t)])
  (setq tabulated-list-padding 2)
  (tabulated-list-init-header))

(defun choicel--render (results label)
  "Display RESULTS with LABEL in the current results buffer."
  (setq header-line-format
        (format "%s: %s | %d results | RET: help  g: search  q: quit"
                label choicel--query (length results))
        tabulated-list-entries
        (mapcar (lambda (row)
                  (list (car row)
                        (vector (symbol-name (car row))
                                (if (string-empty-p (nth 2 row)) "—" (nth 2 row))
                                (or (nth 3 row) ""))))
                results))
  (tabulated-list-print t))

;;;###autoload
(defun choicel (query)
  "Find commands matching QUERY without executing them.
Use the invoking buffer's active keymaps.  Include registered autoloads."
  (interactive (list (read-string "What do you want to do? ")))
  (when (string-empty-p (string-trim query)) (user-error "Enter a search phrase"))
  (let* ((source (if (and (derived-mode-p 'choicel-results-mode)
                          (buffer-live-p choicel--source-buffer))
                     choicel--source-buffer (current-buffer)))
         (commands (choicel--commands))
         (results (with-current-buffer source (choicel--search query commands)))
         (context (with-current-buffer source
                    `((major_mode . ,(symbol-name major-mode))
                      (minor_modes . ,(vconcat
                                      (cl-loop for mode in minor-mode-list
                                               when (and (boundp mode) (symbol-value mode))
                                               collect (symbol-name mode)))))))
         (buffer (get-buffer-create "*choicel*"))
         (token (make-symbol "choicel-search")))
    (with-current-buffer buffer
      (choicel--cancel-pending)
      (choicel-results-mode)
      (setq choicel--source-buffer source choicel--query query
            choicel--search-token token)
      (add-hook 'kill-buffer-hook #'choicel--cancel-pending nil t)
      (add-hook 'change-major-mode-hook #'choicel--cancel-pending nil t)
      (choicel--render results "Keyword search"))
    (pop-to-buffer buffer)
    (when (and (memq choicel-backend '(auto systemone))
               (or choicel-systemone-url (eq choicel-backend 'systemone)))
      (with-current-buffer buffer
        (setq header-line-format "System One searching… | Keyword results below | C-c C-k: cancel"))
      (let ((cancel
             (choicel-systemone-search
              query context commands
              (lambda (entries failure)
                (when (and (buffer-live-p buffer)
                           (eq token (buffer-local-value 'choicel--search-token buffer)))
                  (let ((rows
                         (when (and (not failure) (buffer-live-p source))
                           (with-current-buffer source
                             (cl-loop for entry in entries
                                      when (commandp (car entry))
                                      collect (list (car entry) 0
                                                    (choicel--bindings (car entry))
                                                    (car (split-string (cadr entry) "\n"))))))))
                    (with-current-buffer buffer
                      (setq choicel--cancel-search nil)
                      (if (or failure (not (buffer-live-p source)))
                          (choicel--render results
                                           (format "Keyword fallback (%s)"
                                                   (or failure "Source buffer closed")))
                        (choicel--render
                         (cl-subseq rows 0 (min choicel-max-results (length rows)))
                         "System One")))))))))
        (when (and (buffer-live-p buffer)
                   (eq token (buffer-local-value 'choicel--search-token buffer)))
          (with-current-buffer buffer (setq choicel--cancel-search cancel)))))))

(provide 'choicel)
;;; choicel.el ends here
