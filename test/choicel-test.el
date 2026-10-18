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

;;; choicel-test.el ends here
