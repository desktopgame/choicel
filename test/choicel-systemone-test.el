;;; choicel-systemone-test.el --- Backend tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'choicel)

(defun choicel-test--answer (names)
  "Return a response assigning descending probabilities to NAMES."
  (let ((probabilities (make-hash-table :test 'equal)))
    (cl-loop for name in names for index from 0
             do (puthash name (/ 1.0 (+ index 1)) probabilities))
    (let ((answer (make-hash-table :test 'equal))
          (answers (make-hash-table :test 'equal))
          (data (make-hash-table :test 'equal)))
      (puthash "type" "choice" answer)
      (puthash "choice" (car names) answer)
      (puthash "probabilities" probabilities answer)
      (puthash "command" answer answers)
      (puthash "answers" answers data)
      data)))

(ert-deftest choicel-systemone-chunk-boundaries ()
  (should-not (choicel-systemone--chunks nil 2))
  (should (equal (choicel-systemone--chunks '(a) 2) '((a))))
  (should (equal (choicel-systemone--chunks '(a b) 2) '((a b))))
  (should (equal (choicel-systemone--chunks '(a b c) 2) '((a b) (c))))
  (should-error (choicel-systemone--chunks '(a) 0)))

(ert-deftest choicel-systemone-validates-response ()
  (let ((commands '((dired "Directory") (ignore "Ignore"))))
    (should (equal (choicel-systemone--parse
                    (choicel-test--answer '("dired" "ignore")) commands 1)
                   '((dired "Directory"))))
    (should-error (choicel-systemone--parse
                   (choicel-test--answer '("invented-command" "ignore")) commands 1))
    (should-error (choicel-systemone--parse
                   (choicel-test--answer '("dired")) commands 1))
    (should-error (choicel-systemone--parse (make-hash-table) commands 1))))

(ert-deftest choicel-systemone-parallel-tournament ()
  (let ((choicel-systemone-url "http://example.invalid/v1/systemone")
        (choicel-systemone-chunk-size 2)
        (choicel-systemone-survivors 1)
        (choicel-max-concurrent-requests 2)
        queued seen (active 0) (maximum 0) (finished 0) result)
    (cl-letf (((symbol-function 'choicel-systemone--request)
               (lambda (payload _url _key _timeout callback)
                 (let* ((question (cdr (assq 'command (cdr (assq 'questions payload)))))
                        (names (sort (hash-table-keys (cdr (assq 'criteria question)))
                                     #'string-lessp)))
                   (push names seen)
                   (cl-incf active)
                   (setq maximum (max maximum active))
                   (push (cons names callback) queued)
                   #'ignore))))
      (choicel-systemone-search
       "query" nil '((a "") (b "") (c "") (d "") (e ""))
       (lambda (entries error)
         (should-not error) (setq result entries) (cl-incf finished)))
      ;; Complete newest first, and invoke each completion twice.
      (while queued
        (let ((request (pop queued)))
          (cl-decf active)
          (funcall (cdr request) (choicel-test--answer (car request)) nil)
          (funcall (cdr request) (choicel-test--answer (car request)) nil)))
      (should (= maximum 2))
      (should (= finished 1))
      (should (= (length result) 1))
      (should (member '("a" "b") seen))
      (should (member '("c" "d") seen))
      (should (> (length seen) 2)))))

(ert-deftest choicel-systemone-error-and-cancel ()
  (let ((choicel-systemone-url "http://example.invalid/v1/systemone")
        callback (calls 0) (cancelled 0))
    (cl-letf (((symbol-function 'choicel-systemone--request)
               (lambda (_payload _url _key _timeout cb)
                 (setq callback cb)
                 (lambda () (cl-incf cancelled)))))
      (let ((cancel (choicel-systemone-search
                     "x" nil '((a "") (b ""))
                     (lambda (_entries error) (should error) (cl-incf calls)))))
        (funcall callback nil "Timeout")
        (funcall callback nil "Late error")
        (should (= calls 1))
        (should (> cancelled 0))
        (funcall cancel))
      (setq calls 0)
      (let ((cancel (choicel-systemone-search
                     "x" nil '((a "") (b ""))
                     (lambda (&rest _) (cl-incf calls)))))
        (funcall cancel)
        (funcall callback (choicel-test--answer '("a" "b")) nil)
        (should (= calls 0))))))

(ert-deftest choicel-systemone-http-headers-and-timeout ()
  (let (headers body completion timeout-fn response (calls 0))
    (cl-letf (((symbol-function 'url-retrieve)
               (lambda (_url cb &rest _)
                 (setq headers url-request-extra-headers
                       body url-request-data completion cb
                       response (generate-new-buffer " *choicel-http-test*"))))
              ((symbol-function 'run-at-time)
               (lambda (_seconds _repeat fn &rest args)
                 (setq timeout-fn (lambda () (apply fn args))) nil)))
      (choicel-systemone--request
       '((state . "日本語")) "http://example.invalid" "test-key" 1
       (lambda (_data error) (should error) (cl-incf calls)))
      (should (equal (cdr (assoc "Authorization" headers)) "Bearer test-key"))
      (should (string-match-p "日本語" (decode-coding-string body 'utf-8)))
      (funcall timeout-fn)
      (should-not (buffer-live-p response))
      (funcall completion nil)
      (should (= calls 1)))))

(ert-deftest choicel-systemone-http-invalid-responses ()
  (dolist (case '((500 . "{}") (200 . "not json")))
    (let (response completion failure)
      (cl-letf (((symbol-function 'url-retrieve)
                 (lambda (_url cb &rest _)
                   (setq completion cb
                         response (generate-new-buffer " *choicel-http-test*")))))
        (choicel-systemone--request
         '((state . "test")) "http://example.invalid" nil 10
         (lambda (_data error) (setq failure error)))
        (with-current-buffer response
          (setq-local url-http-response-status (car case))
          (insert "HTTP/1.1 test\r\n\r\n" (cdr case))
          (funcall completion nil))
        (should failure)
        (should-not (buffer-live-p response))))))

(ert-deftest choicel-systemone-ui-fallback ()
  (let ((choicel-backend 'systemone) (choicel-systemone-url nil))
    (save-window-excursion
      (with-temp-buffer
        (choicel "split window")
        (with-current-buffer "*choicel*"
          (should (string-match-p "Keyword fallback" header-line-format))
          (should tabulated-list-entries)))
      (when (get-buffer "*choicel*") (kill-buffer "*choicel*")))))

(ert-deftest choicel-systemone-ignores-stale-ui-completion ()
  (let ((choicel-backend 'systemone)
        (choicel-systemone-url "http://example.invalid") callbacks)
    (save-window-excursion
      (with-temp-buffer
        (let ((source (current-buffer)))
          (cl-letf (((symbol-function 'choicel-systemone-search)
                     (lambda (_query _context _commands callback)
                       (push callback callbacks) #'ignore)))
            (choicel "split window")
            (with-current-buffer source (choicel "save file"))
            (funcall (cadr callbacks) '((ignore "Old answer")) nil)
            (with-current-buffer "*choicel*"
              (should (equal choicel--query "save file"))
              (should (string-match-p "searching" header-line-format)))
            (funcall (car callbacks) '((save-buffer "Save buffer")) nil)
            (with-current-buffer "*choicel*"
              (should (equal (caar tabulated-list-entries) 'save-buffer))
              (should (string-match-p "System One:" header-line-format))))))
      (when (get-buffer "*choicel*") (kill-buffer "*choicel*")))))

(ert-deftest choicel-systemone-empty-and-singleton ()
  (let ((choicel-systemone-url "http://example.invalid") (calls 0))
    (cl-letf (((symbol-function 'choicel-systemone--request)
               (lambda (&rest _) (ert-fail "Unnecessary HTTP request"))))
      (dolist (commands '(nil ((dired "Directory"))))
        (choicel-systemone-search
         "test" nil commands
         (lambda (entries error)
           (should-not error) (should (equal entries commands)) (cl-incf calls))))
      (should (= calls 2)))))

;;; choicel-systemone-test.el ends here
