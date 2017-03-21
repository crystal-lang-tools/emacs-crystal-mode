# emacs-crystal-mode
A minimal crystal mode for emacs, based on ruby-mode (of course)

## Requirements

Depends on package: project-root

It should be configured like
```
(require 'project-root)
(setq project-roots
      '(("generic crystal project"
         :root-contains-files ("shard.yml")
         :filename-regex ,(regexify-ext-list '(cr yml md))
         )))
```
