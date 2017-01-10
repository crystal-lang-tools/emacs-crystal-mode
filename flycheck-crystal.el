;;; flycheck-crystal.el --- Add support for Crystal to Flycheck

;; Version: 0.1
;; Package-Requires: ((flycheck "30"))
;; Keywords: tools crystal

;;; Commentary:

;; This package provides error-checking support for the Crystal language to the
;; Flycheck package.  To use it, have Flycheck installed, then add the following
;; to your init file:
;;
;;    (require 'flycheck-crystal)
;;    (add-hook 'crystal-mode-hook 'flycheck-mode)

;;; Code:

(require 'flycheck)

(flycheck-define-checker crystal-build
  "A Crystal syntax checker using crystal build"
  :command ("crystal"
            "build"
            "--no-codegen"
            "--no-color"
            source-inplace)
  :error-patterns
  ((error line-start "Error in " (file-name) ":" line ":" (message) line-end)
   (error line-start "Syntax error in " (file-name) ":" line ":" (message) line-end)
   (warning line-start "Warning in " (file-name) ":" line ":" (message) line-end)
   )
  :modes crystal-mode
  )

(add-to-list 'flycheck-checkers 'crystal-build)

(provide 'flycheck-crystal)

;;; flycheck-crystal.el ends here
