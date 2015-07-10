(flycheck-define-checker crystal-build
  "A Crystal syntax checker using crystal build"
  :command ("crystal"
            "build"
            "--no-build"
            "--no-color"
            source-inplace)
  :error-patterns
  ((error line-start "Error in " (file-name) ":" line ":" (message) line-end)
   (error line-start "Syntax error in " (file-name) ":" line ":" (message) line-end)
   (warning line-start "Warning in " (file-name) ":" line ":" (message) line-end)
   )
  :modes crystal-mode
  )

(add-to-list 'flycheck-checkers 'my-new-syntax-checker)
