;;; choicel.el --- Discover commands in your Emacs -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; Package-Requires: ((emacs "27.1"))
;; Keywords: help, convenience

;;; Commentary:
;; Run M-x choicel to find loaded commands and their current bindings.
;; Results open help by default; explicit actions can execute a command.

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

(defcustom choicel-display-style 'normal
  "How to display results, independently of action and key bindings.
Normal follows Emacs display rules.  Full-frame temporarily uses one window.
Minibuffer uses the user's completion UI without a results window."
  :group 'choicel :type '(choice (const normal) (const full-frame) (const minibuffer)))

(defcustom choicel-default-action 'help
  "Action taken by `choicel-default-action' on the selected result."
  :group 'choicel :type '(choice (const help) (const execute)))

(defvar-local choicel--source-buffer nil)
(defvar-local choicel--query nil)
(defvar-local choicel--cancel-search nil)
(defvar-local choicel--search-token nil)
(defvar-local choicel--window-configuration nil)
(defvar-local choicel--source-window nil)
(defvar-local choicel--selection-timer nil)
(defvar-local choicel--prefix nil)

(defun choicel--restore-layout ()
  "Cancel pending work and restore the search's original layout."
  (let ((configuration choicel--window-configuration)
        (buffer (current-buffer)))
    (choicel--cancel-pending)
    (setq choicel--window-configuration nil)
    (if (and (window-configuration-p configuration)
             (frame-live-p (window-configuration-frame configuration)))
        (set-window-configuration configuration)
      (let ((window (get-buffer-window buffer)))
        (when window (quit-window nil window))))))

(defun choicel-quit ()
  "Close the results view and restore the original window layout."
  (interactive)
  (choicel--restore-layout))

(defun choicel-execute-command (prefix)
  "Restore the source context, then interactively execute the selected command.
Pass PREFIX to the command, including prompts for its normal arguments."
  (interactive "P")
  (let ((command (tabulated-list-get-id))
        (source choicel--source-buffer)
        (window choicel--source-window))
    (unless (and command (commandp command))
      (user-error "Select a command row first"))
    (unless (buffer-live-p source)
      (user-error "The original buffer has been closed"))
    (choicel--restore-layout)
    (cond ((and (window-live-p window) (eq (window-buffer window) source))
           (select-window window))
          ((get-buffer-window source t)
           (select-window (get-buffer-window source t)))
          (t (switch-to-buffer source)))
    (let ((current-prefix-arg prefix)
          (this-command command)
          (real-this-command command))
      (call-interactively command))))

(defun choicel-default-action (prefix)
  "Perform the configured default action, passing PREFIX when executing."
  (interactive "P")
  (pcase choicel-default-action
    ('help (choicel-describe-command))
    ('execute (choicel-execute-command prefix))
    (_ (user-error "Unknown choicel default action"))))

(defun choicel--cancel-pending ()
  "Cancel work belonging to this results buffer."
  (when choicel--selection-timer (cancel-timer choicel--selection-timer))
  (setq choicel--selection-timer nil)
  (when choicel--cancel-search (funcall choicel--cancel-search))
  (setq choicel--cancel-search nil choicel--search-token nil))

(defun choicel-cancel-search ()
  "Cancel System One search or a pending minibuffer selection."
  (interactive)
  (let ((buffer (if (derived-mode-p 'choicel-results-mode)
                    (current-buffer) (get-buffer "*choicel*"))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (choicel--cancel-pending)
        (setq header-line-format
              (concat "System One cancelled | Keyword results | "
                      (choicel--action-hints)))))
    (message "Choicel search cancelled")))

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
    (define-key map (kbd "RET") #'choicel-default-action)
    (define-key map (kbd "h") #'choicel-describe-command)
    (define-key map (kbd "e") #'choicel-execute-command)
    (define-key map (kbd "q") #'choicel-quit)
    (define-key map (kbd "C-c C-k") #'choicel-cancel-search)
    (define-key map (kbd "g") #'choicel-search-again)
    map))

(define-derived-mode choicel-results-mode tabulated-list-mode "Choicel"
  "Command results.  RET uses the default action; h helps, e executes, q quits."
  (setq tabulated-list-format [("Command" 36 t) ("Keys" 22 t) ("Description" 0 t)])
  (setq tabulated-list-padding 2)
  (tabulated-list-init-header))

(defun choicel--render (results label)
  "Display RESULTS with LABEL in the current results buffer."
  (setq header-line-format
        (format "%s: %s | %d results | %s"
                label choicel--query (length results) (choicel--action-hints))
        tabulated-list-entries
        (mapcar (lambda (row)
                  (list (car row)
                        (vector (symbol-name (car row))
                                (if (string-empty-p (nth 2 row)) "—" (nth 2 row))
                                (or (nth 3 row) ""))))
                results))
  (tabulated-list-print t))

(defun choicel--action-hints ()
  "Describe current action bindings, including user remappings."
  (mapconcat
   (lambda (pair)
     (let ((key (where-is-internal (car pair) (current-local-map) t)))
       (format "%s: %s" (if key (key-description key) "M-x") (cdr pair))))
   `((choicel-default-action . ,(format "default (%s)" choicel-default-action))
     (choicel-describe-command . "help") (choicel-execute-command . "execute")
     (choicel-search-again . "search") (choicel-quit . "quit"))
   "  "))

(defun choicel--minibuffer-select (buffer token)
  "Select a result from BUFFER for search TOKEN using standard completion."
  (when (and (buffer-live-p buffer)
             (eq token (buffer-local-value 'choicel--search-token buffer)))
    (with-current-buffer buffer
      (unwind-protect
          (if (not (buffer-live-p choicel--source-buffer))
              (message "Choicel: the original buffer has been closed")
            (let* ((entries tabulated-list-entries)
                   (names (mapcar (lambda (entry) (symbol-name (car entry))) entries))
                   (annotation
                    (lambda (name)
                      (let* ((entry (cl-find name entries
                                             :key (lambda (row) (symbol-name (car row)))
                                             :test #'equal))
                             (columns (cadr entry)))
                        (when columns
                          (format "  [%s] %s" (aref columns 1)
                                  (truncate-string-to-width (aref columns 2) 100 nil nil t))))))
                   (table
                    (lambda (string predicate action)
                      (if (eq action 'metadata)
                          `(metadata (category . choicel-command)
                                     (display-sort-function . identity)
                                     (cycle-sort-function . identity)
                                     (annotation-function . ,annotation))
                        (complete-with-action action names string predicate)))))
              (if (null names)
                  (message "Choicel: no matches; try another search phrase")
                (let* ((selection (completing-read
                                   (format "Choicel (%s): " choicel-default-action)
                                   table nil t nil nil (car names)))
                       (entry (cl-find selection entries
                                       :key (lambda (row) (symbol-name (car row)))
                                       :test #'equal))
                       (command (car entry))
                       (prefix choicel--prefix))
                  (unless (and (eq token choicel--search-token) (commandp command))
                    (user-error "Choicel selection is no longer available"))
                  (pcase choicel-default-action
                    ('help (choicel--restore-layout) (describe-function command))
                    ('execute
                     (goto-char (point-min))
                     (while (and (not (eobp))
                                 (not (eq (tabulated-list-get-id) command)))
                       (forward-line 1))
                     (unless (eq (tabulated-list-get-id) command)
                       (user-error "Choicel result is no longer available"))
                     (choicel-execute-command prefix))
                    (_ (user-error "Unknown choicel default action")))))))
        (when (eq token choicel--search-token) (choicel--restore-layout))))))

(defun choicel--queue-minibuffer (buffer token)
  "Defer selection for BUFFER and TOKEN until no other minibuffer is active."
  (when (and (buffer-live-p buffer)
             (eq token (buffer-local-value 'choicel--search-token buffer)))
    (with-current-buffer buffer
      (setq choicel--selection-timer
            (run-with-idle-timer
             0.1 nil
             (lambda ()
               (when (and (buffer-live-p buffer)
                          (eq token (buffer-local-value 'choicel--search-token buffer)))
                 (if (active-minibuffer-window)
                     (choicel--queue-minibuffer buffer token)
                   (condition-case nil
                       (choicel--minibuffer-select buffer token)
                     (quit (message "Choicel cancelled")))))))))))

;;;###autoload
(defun choicel (query)
  "Find commands matching QUERY, displaying them for an explicit user action.
Use the invoking buffer's active keymaps.  Include registered autoloads."
  (interactive (list (read-string "What do you want to do? ")))
  (when (string-empty-p (string-trim query)) (user-error "Enter a search phrase"))
  (let* ((caller (current-buffer))
         (view (window-buffer (selected-window)))
         (continuing (and (buffer-live-p view)
                          (with-current-buffer view
                            (and (derived-mode-p 'choicel-results-mode)
                                 choicel--window-configuration
                                 (or (eq caller view)
                                     (eq choicel--source-buffer caller))))))
         (source (if (and (derived-mode-p 'choicel-results-mode)
                          (buffer-live-p choicel--source-buffer))
                     choicel--source-buffer (current-buffer)))
         (configuration (if continuing
                            (buffer-local-value 'choicel--window-configuration view)
                          (current-window-configuration)))
         (source-window (if continuing
                            (buffer-local-value 'choicel--source-window view)
                          (selected-window)))
         (commands (choicel--commands))
         (results (with-current-buffer source (choicel--search query commands)))
         (context (with-current-buffer source
                    `((major_mode . ,(symbol-name major-mode))
                      (minor_modes . ,(vconcat
                                      (cl-loop for mode in minor-mode-list
                                               when (and (boundp mode) (symbol-value mode))
                                               collect (symbol-name mode)))))))
         (buffer (get-buffer-create "*choicel*"))
         (minibuffer-style (eq choicel-display-style 'minibuffer))
         (prefix current-prefix-arg)
         (use-systemone (and (memq choicel-backend '(auto systemone))
                             (or choicel-systemone-url (eq choicel-backend 'systemone))))
         (token (make-symbol "choicel-search")))
    (with-current-buffer buffer
      (choicel--cancel-pending)
      (choicel-results-mode)
      (setq choicel--source-buffer source choicel--query query
            choicel--window-configuration configuration
            choicel--source-window source-window
            choicel--prefix prefix
            choicel--search-token token)
      (add-hook 'kill-buffer-hook #'choicel--cancel-pending nil t)
      (add-hook 'change-major-mode-hook #'choicel--cancel-pending nil t)
      (choicel--render results "Keyword search"))
    (unless minibuffer-style
      (if (eq choicel-display-style 'full-frame)
          (progn (switch-to-buffer buffer) (delete-other-windows))
        (pop-to-buffer buffer)))
    (when (and minibuffer-style (not use-systemone))
      (choicel--minibuffer-select buffer token))
    (when use-systemone
      (when minibuffer-style (message "Choicel: System One searching…"))
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
                         "System One")))
                    (when minibuffer-style
                      (choicel--queue-minibuffer buffer token))))))))
        (when (and (buffer-live-p buffer)
                   (eq token (buffer-local-value 'choicel--search-token buffer)))
          (with-current-buffer buffer (setq choicel--cancel-search cancel)))))))

(provide 'choicel)
;;; choicel.el ends here
