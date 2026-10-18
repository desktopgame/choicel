;;; choicel-metrics.el --- Search timing reports -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep the latest search's timings in memory, without queries or credentials.

;;; Code:
(require 'cl-lib)

(defvar choicel-last-search-metrics nil
  "Hash table containing timings for the latest search, or nil.
Contains no query text, endpoint URL, API key, or response bodies.")
(defvar choicel--metrics-current nil)

(defun choicel--metrics-new ()
  "Create and publish a fresh timing record."
  (let ((metrics (make-hash-table :test 'eq)))
    (puthash 'started (float-time) metrics)
    (puthash 'status 'running metrics)
    (setq choicel-last-search-metrics metrics)))

(defun choicel--metrics-finish (metrics status)
  "Mark METRICS finished with STATUS, without changing finished records."
  (when (and metrics (eq (gethash 'status metrics) 'running))
    (puthash 'total (- (float-time) (gethash 'started metrics)) metrics)
    (puthash 'ready-at (float-time) metrics)
    (puthash 'status status metrics)))

(defun choicel-show-last-search-metrics ()
  "Show timings for the latest search, excluding time spent choosing a command."
  (interactive)
  (unless choicel-last-search-metrics (user-error "Run choicel first"))
  (let* ((metrics choicel-last-search-metrics)
         (requests (reverse (gethash 'requests metrics)))
         (durations (mapcar (lambda (row) (plist-get row :seconds)) requests))
         (count (length requests)))
    (with-help-window "*choicel timings*"
      (princ (format "Choicel search timings\n\nStatus: %s\nCommands: %d\nBackend: %s\n"
                     (gethash 'status metrics) (gethash 'commands metrics 0)
                     (gethash 'backend metrics 'builtin)))
      (when (gethash 'model metrics)
        (princ (format "Model: %s\n" (gethash 'model metrics))))
      (dolist (pair '((collect . "Command collection") (builtin . "Keyword search + keys")
                      (systemone . "System One elapsed") (display . "Final keys + display")
                      (total . "Total until results ready")
                      (selection-delay . "Ready to minibuffer opening")))
        (when (gethash (car pair) metrics)
          (princ (format "%s: %.3f s\n" (cdr pair) (gethash (car pair) metrics)))))
      (when (eq (gethash 'status metrics) 'running)
        (princ (format "Elapsed so far: %.3f s\n"
                       (- (float-time) (gethash 'started metrics)))))
      (princ (format "Chunk size: %s / concurrency: %s / survivors: %s\n"
                     (gethash 'chunk-size metrics "—")
                     (gethash 'concurrency metrics "—")
                     (gethash 'survivors metrics "—")))
      (princ (format "HTTP requests: %d started, %d completed\n"
                     (gethash 'request-count metrics 0) count))
      (when durations
        (princ (format "Request duration min / mean / max: %.3f / %.3f / %.3f s\n"
                       (apply #'min durations) (/ (apply #'+ durations) count)
                       (apply #'max durations))))
      (princ "\nRounds (each round waits for the preceding round):\n")
      (dolist (row (reverse (gethash 'rounds metrics)))
        (princ (format "Round %d: %d candidates, %.3f s\n"
                       (plist-get row :round) (plist-get row :candidates)
                       (plist-get row :seconds))))
      (princ "\nPer request (elapsed includes network, server queue, inference and decoding):\n")
      (dolist (row (sort requests (lambda (a b) (< (plist-get a :id) (plist-get b :id)))))
        (princ (format "#%d  round %d  %d options  %.3f s  %s\n"
                       (plist-get row :id) (plist-get row :round)
                       (plist-get row :options) (plist-get row :seconds)
                       (plist-get row :status))))
      (princ "\nParallel request times overlap; their sum is not wall-clock time.\n")
      (princ "Input/selection time is excluded. No query, URL, key or response is recorded.\n"))))

(provide 'choicel-metrics)
;;; choicel-metrics.el ends here
