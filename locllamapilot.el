;;; locllamapilot.el --- Functions to interface with Llamafiles for code completion
;;
;;; Commentary:
;; This file includes some interactive functions to get code
;; completion suggestions from llamafiles used as http servers.  You
;; can check Mozilla Ocho's docs on how to set that up, it is very
;; straightforward.  There is a package that offers similar
;; functionality, https://github.com/jart/emacs-copilot, however this
;; uses the cli mode of the llamafiles.  By using the http server
;; option, you can send these requests to remote machines hosting the
;; model easily, and you can also forget about the time it will take
;; to load up the model in memory every time you call it.  The mode
;; uses overlays to provide a preview of the code suggestion, which
;; can then be either deleted or inserted into the buffer.  wizardcode
;; model has been in my experience the better performing of the
;; llamafile models provided in the Mozilla Ocho llamafile repo.

(require 'request)

;;; Code:

(defcustom locllamapilot-system-prompt
  "\
You are an Emacs code generator. \
Writing comments is forbidden. \
Writing test code is forbidden. \
Writing English explanations is forbidden. \
Only write code, nothing else."
;Only write until the end of function or end of class."
  "System prompt to provide to the model.  This sets the context of the model."
  :type 'string
  :group 'locllamapilot)

(defcustom locllamapilot-inst-prompt
  "Generate %s code to complete the following markdown block only:\n```%s\n%s"
  "Instruction prompt, this is what the user would submit to the model."
  :type 'string)

(defcustom locllamapilot-code-context-limit
  700
  "Code context limit.
Only these numbers of characters before point
will be passed to the model."   :type 'integer)

(defcustom locllamapilot-max-tokens
  100
  "Maximum number of tokens for model output."
  :type 'integer)

(defun locllamapilot-get-input-code ()
  "Get an area of the buffer to feed up to point to the model."
  ;; TODO: the beginning should be limited to fit into context
  (buffer-substring-no-properties (if (> 0 (- (point) locllamapilot-code-context-limit))
                                      1
                                    (- (point) locllamapilot-code-context-limit)) (point)))

(defun locllamapilot-build-prompt ()
  "Interpolates prompt default string with current language and buffer code."
  (format locllamapilot-inst-prompt
          (locllamapilot-get-prog-lang)
          (locllamapilot-get-prog-lang)
          (format "%s" (locllamapilot-get-input-code))))

(defun locllamapilot-get-prog-lang ()
  "Infers the programming language in the buffer based on current major mode."
  (when (string-match "\\(\\w+\\)" (format "%s" major-mode))
    (match-string 0 (format "%s" major-mode))))

(defface locllamapilot-face
  '((t :inherit shadow))
  "Face for displaying locllamapilot text."
  :group 'cursive)

(defvar-local locllamapilot--overlay nil
  "Overlay for Locllamapilot completion.")

(defun locllamapilot-display (string)
  "Displays the given code completion as overlay.
Argument STRING string to display."
  (let ((ov (make-overlay (point) (point)))
        (pstring (propertize string 'face 'locllamapilot-face)))
    (overlay-put ov 'after-string "")
    (put-text-property 0 1 'cursor t pstring)
    (overlay-put ov 'display pstring)
    (overlay-put ov 'after-string pstring)
    (overlay-put ov 'completion string)
    (overlay-put ov 'start (point))
    (setq locllamapilot--overlay ov)))

(defun locllamapilot-get-json-data (prompt)
  "Json payload to send as body to the model server.
Argument PROMPT user prompt string to provide, should contain buffer's code."
  (setq json-data
           `(
             :model "LLaMA_CPP"
                    :temperature 0
                    :max_tokens ,locllamapilot-max-tokens
             :messages [
                        (("role" . "system")
                         ("content" . ,locllamapilot-system-prompt))
                        (("role" . "user")
                         ("content" . ,prompt))
                        ]))
     json-data)

(defcustom locllamapilot-request-url
  "http://localhost:8080/v1/chat/completions"
  "Url of the llamafile server."
  :type 'string)

(defun locllamapilot-callmodel (prompt)
  "Send http post request to the model server.
Argument PROMPT string containing the user prompt and buffer's code."
  (request-response-data
  (request
    locllamapilot-request-url
    :type "POST"
    :headers '(("Content-Type" . "application/json")
               ("Authorization" . "Bearer no-key"))
    :data (json-encode prompt)
    :parser 'json-read
    :error (cl-function
            (lambda (&rest args &key error-thrown &allow-other-keys)
              (message "Error: %S" error-thrown)))
    :sync t)))

(defun locllamapilot--parse-response (data)
  "Remove possible unwanted characters from the model's response.
Argument DATA Received json data to parse."
  (let ((choices (cdr (assoc 'choices data))))
    (when choices
      (s-replace-regexp "```\\|\\[/*INST\\]\\|<</*SYS>>" ""
      (format "%s" (car (mapcar (lambda (choice)
                                  (cdr (assoc 'content (cdr (assoc 'message choice)))))
                                choices)))))))

(defun locllamapilot-complete ()
  "Provides a completion overlay candidate."
  (interactive)
  (let ((prompt (locllamapilot-build-prompt)))
    (locllamapilot-display
     (locllamapilot--parse-response
      (locllamapilot-callmodel (locllamapilot-get-json-data prompt))))))

(defun locllamapilot-write-complete ()
  "Insert into buffer the overlay candidate and remove the overlay."
  (interactive)
  (when (overlayp locllamapilot--overlay)
    (let ((towrite (overlay-get locllamapilot--overlay 'completion)))
      (save-excursion (goto-char (overlay-get locllamapilot--overlay 'start))
                      (delete-overlay locllamapilot--overlay)
                      (insert towrite))
      (setq locllamapilot--overlay nil))))

(defun locllamapilot-del-complete()
  "Delete current completion overlay candidate."
  (interactive)
  (when (overlayp locllamapilot--overlay)
    (delete-overlay locllamapilot--overlay)
    (setq locllamapilot--overlay nil)))

(provide 'locllamapilot)

;;; locllamapilot.el ends here
