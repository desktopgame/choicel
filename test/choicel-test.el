;;; choicel-test.el --- Tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'choicel)

(defun choicel-test-command () "A test command." (interactive))
(defun choicel-test-function () "An ordinary function.")

(ert-deftest choicel-collects-loaded-commands ()
  (let ((commands (choicel--commands)))
    (should (assq 'choicel-test-command commands))
    (should-not (assq 'choicel-test-function commands))))

(ert-deftest choicel-respects-local-shadowing ()
  (with-temp-buffer
    (let ((saved-global (current-global-map))
          (test-global (make-sparse-keymap))
          (local (make-sparse-keymap)))
      (unwind-protect
          (progn
      (use-global-map test-global)
      (define-key test-global (kbd "C-c t") #'choicel-test-command)
      (use-local-map local)
      (should (equal (choicel--bindings 'choicel-test-command) "C-c t"))
      (define-key local (kbd "C-c t") #'ignore)
      (should (equal (choicel--bindings 'choicel-test-command) ""))
      (define-key local (kbd "C-c l") #'choicel-test-command)
      (should (equal (choicel--bindings 'choicel-test-command) "C-c l")))
        (use-global-map saved-global)))))

(ert-deftest choicel-ranks-name-above-documentation ()
  (with-temp-buffer
    (let ((results (choicel--search "split window"
                                   '((ignore "Split a window")
                                     (split-window-right "Create another view")))))
      (should (eq (caar results) 'split-window-right)))))

(ert-deftest choicel-japanese-hints ()
  (should (member "split" (choicel--terms "ウィンドウを左右に分割したい")))
  (should (member "right" (choicel--terms "ウィンドウを左右に分割したい")) ))

(ert-deftest choicel-empty-and-limited-results ()
  (should-not (choicel--search "zzzzzzzzzz" '((ignore "Nothing"))))
  (let ((choicel-max-results 1))
    (should (= 1 (length (choicel--search "window"
                                        '((split-window-right "Window")
                                          (other-window "Window"))))))))

(ert-deftest choicel-help-does-not-execute ()
  (with-temp-buffer
    (choicel-results-mode)
    (setq tabulated-list-entries
          '((choicel-test-command ["choicel-test-command" "" "Test"])))
    (tabulated-list-print t)
    (let (described)
      (cl-letf (((symbol-function 'describe-function)
                 (lambda (symbol &rest _) (setq described symbol)))
                ((symbol-function 'choicel-test-command)
                 (lambda () (interactive) (ert-fail "Command was executed"))))
        (choicel-describe-command)
        (should (eq described 'choicel-test-command))))))

(ert-deftest choicel-indexes-autoload-without-loading ()
  (let ((symbol (make-symbol "choicel-test-autoload")))
    (unwind-protect
        (progn
          (intern (symbol-name symbol))
          (setq symbol (intern (symbol-name symbol)))
          (autoload symbol "choicel-test-nonexistent-package" "Open a view." t)
          (should (assq symbol (choicel--commands)))
          (should (autoloadp (symbol-function symbol))))
      (unintern (symbol-name symbol) obarray))))

(ert-deftest choicel-common-japanese-entry-queries ()
  (let ((commands '((magit-status "Show repository status")
                    (vc-dir "Show version control directory")
                    (dired "Edit a directory")
                    (find-file "Visit a file")
                    (list-directory "List directory contents"))))
    (should (eq (caar (choicel--search "gitを開きたい" commands)) 'magit-status))
    (should (eq (caar (choicel--search "ディレクトリ一覧を開きたい" commands)) 'dired))
    (should (eq (caar (choicel--search "フォルダを開きたい" commands)) 'dired))
    (should (eq (caar (choicel--search "gitを開きたい"
                                       (assq-delete-all 'magit-status commands)))
                'vc-dir))
    (should-not (assq 'magit-status (choicel--search "gitを開きたい"
                                           '((vc-dir "Version control")))))))

(ert-deftest choicel-display-and-action-are-independent ()
  (dolist (style '(normal full-frame))
    (dolist (action '(help execute))
      (let ((choicel-display-style style)
            (choicel-default-action action)
            (choicel-backend 'builtin)
            described executed)
        (save-window-excursion
          (delete-other-windows)
          (with-temp-buffer
            (switch-to-buffer (current-buffer))
            (insert "source context")
            (goto-char 5)
            (let* ((source (current-buffer))
                   (original (selected-window))
                   (_other (split-window-right))
                   (configuration (current-window-configuration)))
              (cl-letf (((symbol-function 'choicel--commands)
                         (lambda () '((choicel-test-command "Test"))))
                        ((symbol-function 'describe-function)
                         (lambda (command &rest _) (setq described command)))
                        ((symbol-function 'choicel-test-command)
                         (lambda (prefix)
                           (interactive "P")
                           (should (eq (current-buffer) source))
                           (should (eq (selected-window) original))
                           (should (= (point) 5))
                           (should (= (length (window-list)) 2))
                           (should (equal prefix '(4)))
                           (setq executed t))))
                (choicel "test")
                (when (eq style 'full-frame)
                  (should (= (length (window-list)) 1)))
                (choicel-default-action '(4))
                (if (eq action 'help)
                    (progn
                      (should (eq described 'choicel-test-command))
                      (should-not executed)
                      (choicel-quit))
                  (should executed)
                  (should-not described))
                (should (compare-window-configurations
                         configuration (current-window-configuration))))))
          (when (get-buffer "*choicel*") (kill-buffer "*choicel*")))))))

(ert-deftest choicel-research-keeps-original-layout ()
  (let ((choicel-display-style 'full-frame) (choicel-backend 'builtin))
    (save-window-excursion
      (delete-other-windows)
      (with-temp-buffer
        (switch-to-buffer (current-buffer))
        (split-window-right)
        (let ((configuration (current-window-configuration)))
          (choicel "split window")
          (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "save file")))
            (choicel-search-again))
          (should (= (length (window-list)) 1))
          (choicel-quit)
          (should (compare-window-configurations
                   configuration (current-window-configuration)))))
      (when (get-buffer "*choicel*") (kill-buffer "*choicel*")))))

(ert-deftest choicel-keys-are-customizable ()
  (with-temp-buffer
    (choicel-results-mode)
    (use-local-map (copy-keymap choicel-results-mode-map))
    (should (eq (key-binding (kbd "RET")) #'choicel-default-action))
    (define-key (current-local-map) (kbd "e") nil)
    (define-key (current-local-map) (kbd "x") #'choicel-execute-command)
    (should (eq (key-binding (kbd "x")) #'choicel-execute-command))
    (should (string-match-p "x: execute" (choicel--action-hints)))))

(ert-deftest choicel-does-not-execute-with-dead-source ()
  (with-temp-buffer
    (choicel-results-mode)
    (setq choicel--source-buffer (generate-new-buffer " *choicel-dead-source*"))
    (kill-buffer choicel--source-buffer)
    (setq tabulated-list-entries '((ignore ["ignore" "" "Ignore"])))
    (tabulated-list-print t)
    (should-error (choicel-execute-command nil) :type 'user-error)))

;;; choicel-test.el ends here
