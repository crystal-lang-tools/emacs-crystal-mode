;;; crystal-mode.el --- Major mode for editing Crystal files

;; Copyright (C) 2015 Jason Pellerin
;; Authors: Jason Pellerin
;; URL: https://github.com/crystal-lang-tools/emacs-crystal-mode
;; Created: Tue Jun 23 2015
;; Keywords: languages crystal
;; Version: 0.1
;; Package-Requires: ((emacs "24.3"))


;; Based on on ruby-mode.el

;; This file is not part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Provides font-locking, indentation support, and navigation for Crystal code.
;;
;; If you're installing manually, you should add this to your .emacs
;; file after putting it on your load path:
;;
;;    (autoload 'crystal-mode "crystal-mode" "Major mode for crystal files" t)
;;    (add-to-list 'auto-mode-alist '("\\.cr$" . crystal-mode))
;;    (add-to-list 'interpreter-mode-alist '("crystal" . crystal-mode))
;;
;; Still needs more docstrings; search below for TODO.

;;; Code:

(defgroup crystal nil
  "Major mode for editing Crystal code."
  :prefix "crystal-"
  :group 'languages)

(defconst crystal-block-beg-keywords
  '("class" "module" "def" "if" "unless" "case" "while" "until" "for" "begin" "do"
    "macro" "lib" "enum" "struct" "describe" "it")
  "Keywords at the beginning of blocks.")

(defconst crystal-block-beg-re
  (regexp-opt crystal-block-beg-keywords)
  "Regexp to match the beginning of blocks.")

(defconst crystal-non-block-do-re
  (regexp-opt '("while" "until" "rescue") 'symbols)
  "Regexp to match keywords that nest without blocks.")

(defconst crystal-indent-beg-re
  (concat "^\\(\\s *" (regexp-opt '("class" "module" "def" "macro" "lib" "enum" "struct"))
          "\\|"
          (regexp-opt '("if" "unless" "case" "while" "until" "for" "begin"))
          "\\)\\_>")
  "Regexp to match where the indentation gets deeper.")

(defconst crystal-modifier-beg-keywords
  '("if" "unless" "while" "until")
  "Modifiers that are the same as the beginning of blocks.")

(defconst crystal-modifier-beg-re
  (regexp-opt crystal-modifier-beg-keywords)
  "Regexp to match modifiers same as the beginning of blocks.")

(defconst crystal-modifier-re
  (regexp-opt (cons "rescue" crystal-modifier-beg-keywords))
  "Regexp to match modifiers.")

(defconst crystal-block-mid-keywords
  '("then" "else" "elsif" "when" "rescue" "ensure")
  "Keywords where the indentation gets shallower in middle of block statements.")

(defconst crystal-block-mid-re
  (regexp-opt crystal-block-mid-keywords)
  "Regexp to match where the indentation gets shallower in middle of block statements.")

(defconst crystal-block-op-keywords
  '("and" "or" "not")
  "Regexp to match boolean keywords.")

(defconst crystal-block-hanging-re
  (regexp-opt (append crystal-modifier-beg-keywords crystal-block-op-keywords))
  "Regexp to match hanging block modifiers.")

(defconst crystal-block-end-re "\\_<end\\_>")

(defconst crystal-defun-beg-re
  '"\\(def\\|class\\|module\\|macro\\|lib\\|struct\\|enum\\)"
  "Regexp to match the beginning of a defun, in the general sense.")

(defconst crystal-attr-re
  '"\\(@\\[\\)\\(.*\\)\\(\\]\\)"
  "Regexp to match attributes preceding a method or type")

(defconst crystal-singleton-class-re
  "class\\s *<<"
  "Regexp to match the beginning of a singleton class context.")

(eval-and-compile
  (defconst crystal-here-doc-beg-re
  "\\(<\\)<\\(-\\)?\\(\\([a-zA-Z0-9_]+\\)\\|[\"]\\([^\"]+\\)[\"]\\|[']\\([^']+\\)[']\\)"
  "Regexp to match the beginning of a heredoc.")

  (defconst crystal-expression-expansion-re
    "\\(?:[^\\]\\|\\=\\)\\(\\\\\\\\\\)*\\(#\\({[^}\n\\\\]*\\(\\\\.[^}\n\\\\]*\\)*}\\|\\(\\$\\|@\\|@@\\)\\(\\w\\|_\\)+\\|\\$[^a-zA-Z \n]\\)\\)"))


(defun crystal-here-doc-end-match ()
  "Return a regexp to find the end of a heredoc.

This should only be called after matching against `crystal-here-doc-beg-re'."
  (concat "^"
          (if (match-string 2) "[ \t]*" nil)
          (regexp-quote
           (or (match-string 4)
               (match-string 5)
               (match-string 6)))))

(defconst crystal-delimiter
  (concat "[?$/%(){}#\"'`.:]\\|<<\\|\\[\\|\\]\\|\\_<\\|\\<\\("
          crystal-block-beg-re
          "\\)\\_>\\|" crystal-block-end-re
          "\\|^=begin\\|" crystal-here-doc-beg-re))

(defconst crystal-negative
  (concat "^[ \t]*\\(\\(" crystal-block-mid-re "\\)\\>\\|"
          crystal-block-end-re "\\|}\\|\\]\\)")
  "Regexp to match where the indentation gets shallower.")

(defconst crystal-operator-re "[-,.+*/%&|^~=<>:]\\|\\\\$"
  "Regexp to match operators.")

(defconst crystal-symbol-chars "a-zA-Z0-9_"
  "List of characters that symbol names may contain.")

(defconst crystal-symbol-re (concat "[" crystal-symbol-chars "]")
  "Regexp to match symbols.")

(defvar crystal-use-smie t)

(defvar crystal-mode-map
  (let ((map (make-sparse-keymap)))
    (unless crystal-use-smie
      (define-key map (kbd "M-C-b") 'crystal-backward-sexp)
      (define-key map (kbd "M-C-f") 'crystal-forward-sexp)
      (define-key map (kbd "M-C-q") 'crystal-indent-exp))
    (when crystal-use-smie
      (define-key map (kbd "M-C-d") 'smie-down-list))
    (define-key map (kbd "M-C-p") 'crystal-beginning-of-block)
    (define-key map (kbd "M-C-n") 'crystal-end-of-block)
    (define-key map (kbd "C-c {") 'crystal-toggle-block)
    (define-key map (kbd "C-c '") 'crystal-toggle-string-quotes)
    map)
  "Keymap used in Crystal mode.")

(defvar crystal-buffer-name "*crystal*")

(easy-menu-define
  crystal-mode-menu
  crystal-mode-map
  "Crystal Mode Menu"
  '("Crystal"
    ["Beginning of Block" crystal-beginning-of-block t]
    ["End of Block" crystal-end-of-block t]
    ["Toggle Block" crystal-toggle-block t]
    "--"
    ["Toggle String Quotes" crystal-toggle-string-quotes t]
    "--"
    ["Backward Sexp" crystal-backward-sexp
     :visible (not crystal-use-smie)]
    ["Backward Sexp" backward-sexp
     :visible crystal-use-smie]
    ["Forward Sexp" crystal-forward-sexp
     :visible (not crystal-use-smie)]
    ["Forward Sexp" forward-sexp
     :visible crystal-use-smie]
    ["Indent Sexp" crystal-indent-exp
     :visible (not crystal-use-smie)]
    ["Indent Sexp" prog-indent-sexp
     :visible crystal-use-smie]
    "--"
    ["Format" crystal-format t]))

(defvar crystal-mode-syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?\' "\"" table)
    (modify-syntax-entry ?\" "\"" table)
    (modify-syntax-entry ?\` "\"" table)
    (modify-syntax-entry ?# "<" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?\\ "\\" table)
    (modify-syntax-entry ?$ "." table)
    (modify-syntax-entry ?_ "_" table)
    (modify-syntax-entry ?: "_" table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?& "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?% "." table)
    (modify-syntax-entry ?= "." table)
    (modify-syntax-entry ?/ "." table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?* "." table)
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?\; "." table)
    (modify-syntax-entry ?\( "()" table)
    (modify-syntax-entry ?\) ")(" table)
    (modify-syntax-entry ?\{ "(}" table)
    (modify-syntax-entry ?\} "){" table)
    (modify-syntax-entry ?\[ "(]" table)
    (modify-syntax-entry ?\] ")[" table)
    table)
  "Syntax table to use in Crystal mode.")

(defcustom crystal-indent-tabs-mode nil
  "Indentation can insert tabs in Crystal mode if this is non-nil."
  :type 'boolean
  :group 'crystal
  :safe 'booleanp)

(defcustom crystal-indent-level 2
  "Indentation of Crystal statements."
  :type 'integer
  :group 'crystal
  :safe 'integerp)

(defcustom crystal-executable "crystal"
  "Location of Crystal executable."
  :type 'string
  :group 'crystal)

(defcustom crystal-comment-column (default-value 'comment-column)
  "Indentation column of comments."
  :type 'integer
  :group 'crystal
  :safe 'integerp)

(defconst crystal-alignable-keywords '(if while unless until begin case for def macro class)
  "Keywords that can be used in `crystal-align-to-stmt-keywords'.")

(defcustom crystal-align-to-stmt-keywords '(def)
  "Keywords after which we align the expression body to statement.

When nil, an expression that begins with one these keywords is
indented to the column of the keyword.  Example:

  tee = if foo
          bar
        else
          qux
        end

If this value is t or contains a symbol with the name of given
keyword, the expression is indented to align to the beginning of
the statement:

  tee = if foo
    bar
  else
    qux
  end

Only has effect when `crystal-use-smie' is t.
"
  :type `(choice
          (const :tag "None" nil)
          (const :tag "All" t)
          (repeat :tag "User defined"
                  (choice ,@(mapcar
                             (lambda (kw) (list 'const kw))
                             crystal-alignable-keywords))))
  :group 'crystal
  :safe 'listp
  :version "24.4")

(defcustom crystal-align-chained-calls nil
  "If non-nil, align chained method calls.


Each method call on a separate line will be aligned to the column
of its parent.

Only has effect when `crystal-use-smie' is t."
  :type 'boolean
  :group 'crystal
  :safe 'booleanp
  :version "24.4")

(defcustom crystal-deep-arglist t
  "Deep indent lists in parenthesis when non-nil.
Also ignores spaces after parenthesis when `space'.
Only has effect when `crystal-use-smie' is nil."
  :type 'boolean
  :group 'crystal
  :safe 'booleanp)

;; FIXME Woefully under documented.  What is the point of the last `t'?.
(defcustom crystal-deep-indent-paren '(?\( ?\[ ?\] t)
  "Deep indent lists in parenthesis when non-nil.
The value t means continuous line.
Also ignores spaces after parenthesis when `space'.
Only has effect when `crystal-use-smie' is nil."
  :type '(choice (const nil)
                 character
                 (repeat (choice character
                                 (cons character (choice (const nil)
                                                         (const t)))
                                 (const t) ; why?
                                 )))
  :group 'crystal)

(defcustom crystal-deep-indent-paren-style 'space
  "Default deep indent style.
Only has effect when `crystal-use-smie' is nil."
  :type '(choice (const t) (const nil) (const space))
  :group 'crystal)

(defcustom crystal-encoding-map
  '((us-ascii       . nil)       ;; Do not put coding: us-ascii
    (shift-jis      . cp932)     ;; Emacs charset name of Shift_JIS
    (shift_jis      . cp932)     ;; MIME charset name of Shift_JIS
    (japanese-cp932 . cp932))    ;; Emacs charset name of CP932
  "Alist to map encoding name from Emacs to Crystal.
Associating an encoding name with nil means it needs not be
explicitly declared in magic comment."
  :type '(repeat (cons (symbol :tag "From") (symbol :tag "To")))
  :group 'crystal)

(defcustom crystal-insert-encoding-magic-comment nil
  "Insert a magic Crystal encoding comment upon save if this is non-nil.
The encoding will be auto-detected.  The format of the encoding comment
is customizable via `crystal-encoding-magic-comment-style'.

When set to `always-utf8' an utf-8 comment will always be added,
even if it's not required."
  :type 'boolean :group 'crystal)

(defcustom crystal-encoding-magic-comment-style 'crystal
  "The style of the magic encoding comment to use."
  :type '(choice
          (const :tag "Emacs Style" emacs)
          (const :tag "Crystal Style" crystal)
          (const :tag "Custom Style" custom))
  :group 'crystal
  :version "24.4")

(defcustom crystal-custom-encoding-magic-comment-template "# encoding: %s"
  "A custom encoding comment template.
It is used when `crystal-encoding-magic-comment-style' is set to `custom'."
  :type 'string
  :group 'crystal
  :version "24.4")

(defcustom crystal-use-encoding-map t
  "Use `crystal-encoding-map' to set encoding magic comment if this is non-nil."
  :type 'boolean :group 'crystal)

;;; SMIE support

(require 'smie)

(defconst crystal-smie-grammar
  (smie-prec2->grammar
   (smie-merge-prec2s
    (smie-bnf->prec2
     '((id)
       (insts (inst) (insts ";" insts))
       (inst (exp) (inst "iuwu-mod" exp)
             ;; Somewhat incorrect (both can be used multiple times),
             ;; but avoids lots of conflicts:
             (exp "and" exp) (exp "or" exp))
       (exp  (exp1) (exp "," exp) (exp "=" exp)
             (id " @ " exp))
       (exp1 (exp2) (exp2 "?" exp1 ":" exp1))
       (exp2 (exp3) (exp3 "." exp2))
       (exp3 ("def" insts "end")
             ("begin" insts-rescue-insts "end")
             ("do" insts "end")
             ("class" insts "end") ("module" insts "end") ("struct" insts "end")
             ("lib" insts "end") ("enum" insts "end")
             ("[" expseq "]")
             ("{" hashvals "}")
             ("{" insts "}")
             ("{{" exp "}}")
             ("{{" id "}}")
             ("while" insts "end")
             ("until" insts "end")
             ("unless" insts "end")
             ("if" if-body "end")
             ("for" for-body "end")
             ("->{" proc-body "}")
             ("macro" insts "end")
             ("{%" exp "%}")
             ("{%for%}" insts "{%end%}")
             ("{%if%}" if-macro-body "{%end%}")
             ("{%unless%}" insts "{%end%}")
             ("case"  cases "end")
             ("lib" insts "end")
             ("struct" insts "end")
             ("enum" insts "end")
             ("fun" insts "end")
             ("type" insts "end"))
       ;;(macro-cmd (inst) (forexp))
       ;;(macro-cmds (macro-cmd) (macro-cmds ";" macro-cmds))
       ;;(macro-start ("{%" macro-cmd "%}"))
       ;;(macro-block (macro-start macroinsts "{%end%}"))
       ;;(macro-code ("{%" macro-cmds "%}"))
       ;; FIXME this is wrong
       ;;(macro-inst (inst) (macro-block) (macro-code))
       ;;(macro-insts (macro-inst) (macro-insts ";" macro-insts))
       ;;(macro-body (macro-insts))
       (macro-exp (for-head))
       (formal-params ("opening-|" exp "closing-|"))
       (for-body (for-head ";" insts))
       (for-head (exp "in" exp))
       (proc-body (insts))
       (cases (exp "then" insts)
              (cases "when" cases) (insts "else" insts))
       (expseq (exp) );;(expseq "," expseq)
       (hashvals (id "=>" exp1) (hashvals "," hashvals))
       (insts-rescue-insts (insts)
                           (insts-rescue-insts "rescue" insts-rescue-insts)
                           (insts-rescue-insts "ensure" insts-rescue-insts))
       (itheni (insts) (exp "then" insts))
       (ielsei (itheni) (itheni "else" insts))
       (if-body (ielsei) (if-body "elsif" if-body))
       (itheni-macro (insts) (exp "{%then%}" insts))
       (ielsei-macro (itheni-macro) (itheni-macro "{%else%}" insts))
       (if-macro-body (ielsei-macro) (if-macro-body "{%elsif%}" if-macro-body))
       )

     '((nonassoc "in") (assoc ";") (right " @ ")
       (assoc ",") (right "="))
     '((assoc "when"))
     '((assoc "elsif"))
     '((assoc "{%elsif%}"))
     '((assoc "rescue" "ensure"))
     '((assoc ",")))

    (smie-precs->prec2
     '((right "=")
       (right "+=" "-=" "*=" "/=" "%=" "**=" "&=" "|=" "^="
              "<<=" ">>=" "&&=" "||=")
       (left ".." "...")
       (left "+" "-")
       (left "*" "/" "%" "**")
       (left "&&" "||")
       (left "^" "&" "|")
       (nonassoc "<=>")
       (nonassoc ">" ">=" "<" "<=")
       (nonassoc "==" "===" "!=")
       (nonassoc "=~" "!~")
       (left "<<" ">>")
       (right "."))))))

(defun crystal-smie--eoms ()
  (save-excursion
    (forward-char -2)
    (looking-at "%}")
    )
  )

(defun crystal-smie--bosp ()
  (save-excursion (skip-chars-backward " \t")
                  (or (bolp) (memq (char-before) '(?\; ?=)))))

(defun crystal-smie--implicit-semi-p ()
  (save-excursion
    (skip-chars-backward " \t")
    (not (or (bolp)
             (memq (char-before) '(?\[ ?\())
             (and (memq (char-before)
                        '(?\; ?- ?+ ?* ?/ ?: ?. ?, ?\\ ?& ?> ?< ?% ?~ ?^))
                  ;; Not a binary operator symbol.
                  (not (eq (char-before (1- (point))) ?:))
                  ;; Not the end of a regexp or a percent literal.
                  (not (memq (car (syntax-after (1- (point)))) '(7 15))))
             (and (eq (char-before) ?\?)
                  (equal (save-excursion (crystal-smie--backward-token)) "?"))
             (and (eq (char-before) ?=)
                  ;; Not a symbol :==, :!=, or a foo= method.
                  (string-match "\\`\\s." (save-excursion
                                            (crystal-smie--backward-token))))
             (and (eq (char-before) ?|)
                  (member (save-excursion (crystal-smie--backward-token))
                          '("|" "||")))
             (and (eq (car (syntax-after (1- (point)))) 2)
                  (member (save-excursion (crystal-smie--backward-token))
                          '("iuwu-mod" "and" "or")))
             (save-excursion
               (forward-comment 1)
               (eq (char-after) ?.))))))

(defun crystal-smie--redundant-do-p (&optional skip)
  (save-excursion
    (if skip (backward-word 1))
    (member (nth 2 (smie-backward-sexp ";")) '("while" "until" "for"))))

;; this handles "macro def ... end" blocks
(defun crystal-smie--redundant-macro-def-p (&optional skip)
  (save-excursion
    (if skip (backward-word 1))
    (member (nth 2 (smie-backward-sexp ";")) '("macro"))))

(defun crystal-smie--opening-pipe-p ()
  (save-excursion
    (if (eq ?| (char-before)) (forward-char -1))
    (skip-chars-backward " \t\n")
    (or (eq ?\{ (char-before))
        (looking-back "\\_<do" (- (point) 2)))))

(defun crystal-smie--closing-pipe-p ()
  (save-excursion
    (if (eq ?| (char-before)) (forward-char -1))
    (and (re-search-backward "|" (line-beginning-position) t)
         (crystal-smie--opening-pipe-p))))

(defun crystal-smie--args-separator-p (pos)
  (and
   (< pos (line-end-position))
   (or (eq (char-syntax (preceding-char)) '?w)
       ;; FIXME: Check that the preceding token is not a keyword.
       ;; This isn't very important most of the time, though.
       (and (memq (preceding-char) '(?! ??))
            (eq (char-syntax (char-before (1- (point)))) '?w)))
   (save-excursion
     (goto-char pos)
     (or (and (eq (char-syntax (char-after)) ?w)
              (not (looking-at (regexp-opt '("unless" "if" "while" "until" "or"
                                             "else" "elsif" "do" "end" "and")
                                           'symbols))))
         (memq (car (syntax-after pos)) '(7 15))
         (looking-at "[([]\\|[-+!~]\\sw\\|:\\(?:\\sw\\|\\s.\\)")))))

(defun crystal-smie--at-dot-call ()
  (and (eq ?w (char-syntax (following-char)))
       (eq (char-before) ?.)
       (not (eq (char-before (1- (point))) ?.))))

(defun crystal-smie--end-of-macro ()
  "Go to the end of the enclosing macro"
  (re-search-forward "%}")
  )

(defun crystal-smie--forward-token ()
  (let ((pos (point)))
    (skip-chars-forward " \t")

    (cond
     ((looking-at "{%")
      ;; (message "at a macro stmt")
      (forward-char 2)
      (skip-chars-forward " \t")
      (let ((tok (smie-default-forward-token)))
        (if (member tok '("end" "else" "elsif"))
            (concat "{%" tok "%}")
          ";"
          )
        )
      ;; (let ((tok (concat "{%" (smie-default-forward-token) "%}")))
      ;;   (message "at %s %s" (point) (char-after))
      ;;   (re-search-forward "%}")
      ;;   (message "NOW at %s %s" (point) (char-after))
      ;;   (cond (member tok  tok)
      ;;         (t ";"))
      ;;   )
      )
     ((and (looking-at "\n") (looking-at "\\s\""))  ;A heredoc.
      ;; Tokenize the whole heredoc as semicolon.
      (goto-char (scan-sexps (point) 1))
      ";")
     ((and (looking-at "[\n#]")
           (crystal-smie--implicit-semi-p)) ;Only add implicit ; when needed.
      (if (eolp) (forward-char 1) (forward-comment 1))
      ";")
     (t
      (forward-comment (point-max))
      (cond
       ((and (< pos (point))
             (save-excursion
               (crystal-smie--args-separator-p (prog1 (point) (goto-char pos)))))
        " @ ")
       ((looking-at ":\\s.+")
        (goto-char (match-end 0)) (match-string 0)) ;bug#15208.
       ((looking-at "\\s\"") "")                    ;A string.
       (t
        (let ((dot (crystal-smie--at-dot-call))
              (tok (smie-default-forward-token)))
          ;;(message "default forward tok '%s'" tok)
          (when dot
            (setq tok (concat "." tok)))
          (cond
           ((member tok '("unless" "if" "while" "until"))
            (if (save-excursion (forward-word -1) (crystal-smie--bosp))
                tok "iuwu-mod"))
           ((string-match-p "\\`|[*&]?\\'" tok)
            (forward-char (- 1 (length tok)))
            (setq tok "|")
            (cond
             ((crystal-smie--opening-pipe-p) "opening-|")
             ((crystal-smie--closing-pipe-p) "closing-|")
             (t tok)))
           ((and (equal tok "") (looking-at "\\\\\n"))
            (goto-char (match-end 0)) (crystal-smie--forward-token))
           ((equal tok "def")
            (cond
             ((not (crystal-smie--redundant-macro-def-p 'skip)) tok)
             ((> (save-excursion (forward-comment (point-max)) (point))
                 (line-end-position))
              (crystal-smie--forward-token)) ;Fully redundant.
             (t ";")))
           ((equal tok "class")
            (cond
             ((> (save-excursion (forward-comment (point-max)) (point))
                 (line-end-position))
              (crystal-smie--forward-token)) ;Fully redundant.
             (t ";")))
           ((equal tok "do")
            (cond
             ((not (crystal-smie--redundant-do-p 'skip)) tok)
             ((> (save-excursion (forward-comment (point-max)) (point))
                 (line-end-position))
              (crystal-smie--forward-token)) ;Fully redundant.
             (t ";")))
           (t
            ;;(message "forward '%s'" tok)
            tok)
           ))))))))

(defun crystal-smie--backward-token ()
  (let ((pos (point)))
    (forward-comment (- (point)))

    (cond
     ;; FIXME why do these never fire?
     ;; treat macro expr similarly to heredocs? go backwards and tokenize
     ;; as the last token inside of the macro expr
     ;;((looking-at crystal-macro-cmd-re) "{%end%}")
     ;;((looking-at crystal-macro-end-cmd-re) (match-string 1))
     ((looking-back "%}")
      ;; (message "looking back at a macro cmd")
      ;; scan backawards to {%
      (re-search-backward "{%")
      ;; (message "at %s %s" (point) (char-after))
      (save-excursion
        (forward-char 2)
        (skip-chars-forward " \t")
        ;; fixme only if token is in if/else/for/end/while/unless
        (let ((tok (smie-default-forward-token)))
          (if (member tok '("if" "else" "end" "elsif" "unless" "for" "while"))
              (concat "{%" tok "%}")
            ";"))))
     ((and (> pos (line-end-position)) (crystal-smie--implicit-semi-p))
      (skip-chars-forward " \t") ";")
     ((and (bolp) (not (bobp)))         ;Presumably a heredoc.
      ;; Tokenize the whole heredoc as semicolon.
      (goto-char (scan-sexps (point) -1))
      ;; (message "back to heredoc")
      ";")
     ((and (> pos (point)) (not (bolp))
           (crystal-smie--args-separator-p pos))
      ;; We have "ID SPC ID", which is a method call, but it binds less tightly
      ;; than commas, since a method call can also be "ID ARG1, ARG2, ARG3".
      ;; In some textbooks, "e1 @ e2" is used to mean "call e1 with arg e2".
      " @ ")
     (t
      (let ((tok (smie-default-backward-token))
            (dot (crystal-smie--at-dot-call)))
        ;;(message "default backward tok is '%s'" tok)
        (when dot
          ;; (message "back dot")
          (setq tok (concat "." tok)))
        (when (and (eq ?: (char-before)) (string-match "\\`\\s." tok))
          ;; (message "back :")
          (forward-char -1) (setq tok (concat ":" tok))) ;; bug#15208.
        (cond
         ((member tok '("unless" "if" "while" "until"))
          ;; (message "back if while")
          (if (crystal-smie--bosp)
              tok "iuwu-mod"))
         ((equal tok "|")
          ;; (message "back pipe")
          (cond
           ((crystal-smie--opening-pipe-p) "opening-|")
           ((crystal-smie--closing-pipe-p) "closing-|")
           (t tok)))
         ((string-match-p "\\`|[*&]\\'" tok)
          ;; (message "back backtick")
          (forward-char 1)
          (substring tok 1))
         ((and (equal tok "") (eq ?\\ (char-before)) (looking-at "\n"))
          ;; (message "back escaped")
          (forward-char -1) (crystal-smie--backward-token))
         ((equal tok "def")
           ;; (message "back def")
          (cond
           ((not (crystal-smie--redundant-macro-def-p)) tok)
           ((> (save-excursion (forward-word 1)
                               (forward-comment (point-max)) (point))
               (line-end-position))
            (crystal-smie--backward-token)) ;Fully redundant.
           (t ";")))
         ((equal tok "do")
          ;; (message "back do")
          (cond
           ((not (crystal-smie--redundant-do-p)) tok)
           ((> (save-excursion (forward-word 1)
                               (forward-comment (point-max)) (point))
               (line-end-position))
            (crystal-smie--backward-token)) ;Fully redundant.
           (t ";")))
         (t
          ;;(message "backward '%s'" tok)
          tok)))))))

(defun crystal-smie--indent-to-stmt ()
  (save-excursion
    (smie-backward-sexp ";")
    (cons 'column (smie-indent-virtual))))

(defun crystal-smie--indent-to-stmt-p (keyword)
  (or (eq t crystal-align-to-stmt-keywords)
      (memq (intern keyword) crystal-align-to-stmt-keywords)))

(defun crystal-smie-rules (kind token)
   (message "indent '%s' '%s'" kind token)
  (pcase (cons kind token)
    (`(:elem . basic) crystal-indent-level)
    ;; "foo" "bar" is the concatenation of the two strings, so the second
    ;; should be aligned with the first.
    (`(:elem . args) (if (looking-at "\\s\"") 0))
    ;; (`(:after . ",") (smie-rule-separator kind))
    (`(:after . ,(or `"{%else%}" `"{%elsif%}" ))
      (smie-rule-parent crystal-indent-level)
     )
    (`(:before . ";")
     ;; (message "Before ;")
     (cond
      ((smie-rule-parent-p "def" "begin" "do" "class" "module" "{%for%}"
                           "while" "until" "unless" "macro" "lib" "enum" "struct"
                           "if" "then" "elsif" "else" "when" "{%if%}"
                           "{%elsif%}" "{%else%}" "{%unless%}"
                           "rescue" "ensure" "{")
       (message "Still got this one %s" (smie-indent--parent))
       (smie-rule-parent crystal-indent-level))
      ;; For (invalid) code between switch and case.
      ;; (if (smie-parent-p "switch") 4)
      ))

    (`(:before . ,(or `"(" `"[" `"{"))
     ;; (message "Before ( [ {")
     (cond
      ((and (equal token "{")
            (not (smie-rule-prev-p "(" "{" "[" "," "=>" "=" "return" ";"))
            (save-excursion
              (forward-comment -1)
              (not (eq (preceding-char) ?:))))
       ;; Curly block opener.
       ;; (message "curly block opener")
       (crystal-smie--indent-to-stmt))
      ((smie-rule-hanging-p)
       ;; (message "hanging p")
       ;; Treat purely syntactic block-constructs as being part of their parent,
       ;; when the opening token is hanging and the parent is not an
       ;; open-paren.
       (cond
        ((eq (car (smie-indent--parent)) t) nil)
        ;; When after `.', let's always de-indent,
        ;; because when `.' is inside the line, the
        ;; additional indentation from it looks out of place.
        ((smie-rule-parent-p ".")
         (let (smie--parent)
           (save-excursion
             ;; Traverse up the parents until the parent is "." at
             ;; indentation, or any other token.
             (while (and (let ((parent (smie-indent--parent)))
                           (goto-char (cadr parent))
                           (save-excursion
                             (unless (integerp (car parent)) (forward-char -1))
                             (not (crystal-smie--bosp))))
                         (progn
                           (setq smie--parent nil)
                           (smie-rule-parent-p "."))))
             (smie-rule-parent))))
        (t (smie-rule-parent))))))
    (`(:after . ,(or `"(" "[" "{"))
     ;; FIXME: Shouldn't this be the default behavior of
     ;; `smie-indent-after-keyword'?
     ;; (message "After ([{")
     (save-excursion
       (forward-char 1)
       (skip-chars-forward " \t")
       ;; `smie-rule-hanging-p' is not good enough here,
       ;; because we want to reject hanging tokens at bol, too.
       (unless (or (eolp) (forward-comment 1))
         (cons 'column (current-column)))))
    (`(:before . " @ ")
     ;; (message "Before @")
     (save-excursion
       (skip-chars-forward " \t")
       (cons 'column (current-column))))
    (`(:before . "do") (crystal-smie--indent-to-stmt))
    (`(:before . ".")
     (if (smie-rule-sibling-p)
         (and crystal-align-chained-calls 0)
       crystal-indent-level))
    (`(:before . ,(or `"else" `"then" `"elsif" `"rescue" `"ensure" `"{%else%}" `"{%elsif%}"))
     (smie-rule-parent))
    (`(:before . "when")
     ;; Align to the previous `when', but look up the virtual
     ;; indentation of `case'.
     (if (smie-rule-sibling-p) 0 (smie-rule-parent)))
    (`(:after . ,(or "=" "iuwu-mod" "+" "-" "*" "/" "&&" "||" "%" "**" "^" "&"
                     "<=>" ">" "<" ">=" "<=" "==" "===" "!=" "<<" ">>"
                     "+=" "-=" "*=" "/=" "%=" "**=" "&=" "|=" "^=" "|"
                     "<<=" ">>=" "&&=" "||=" "and" "or"))
     (and (smie-rule-parent-p ";" nil)
          (smie-indent--hanging-p)
          crystal-indent-level))
    (`(:after . ,(or "?" ":")) crystal-indent-level)
    (`(:before . ,(guard (memq (intern-soft token) crystal-alignable-keywords)))
     (when (not (crystal--at-indentation-p))
       (if (crystal-smie--indent-to-stmt-p token)
           (crystal-smie--indent-to-stmt)
         (cons 'column (current-column)))))
    ))

(defun crystal--at-indentation-p (&optional point)
  (save-excursion
    (unless point (setq point (point)))
    (forward-line 0)
    (skip-chars-forward " \t")
    (eq (point) point)))

(defun crystal-imenu-create-index-in-block (prefix beg end)
  "Create an imenu index of methods inside a block."
  (let ((index-alist '()) (case-fold-search nil)
        name next pos decl sing)
    (goto-char beg)
    (while (re-search-forward "^\\s *\\(\\(class\\s +\\|\\(class\\s *<<\\s *\\)\\|module\\s +\\)\\([^\(<\n ]+\\)\\|\\(def\\|alias\\)\\s +\\([^\(\n ]+\\)\\)" end t)
      (setq sing (match-beginning 3))
      (setq decl (match-string 5))
      (setq next (match-end 0))
      (setq name (or (match-string 4) (match-string 6)))
      (setq pos (match-beginning 0))
      (cond
       ((string= "alias" decl)
        (if prefix (setq name (concat prefix name)))
        (push (cons name pos) index-alist))
       ((string= "def" decl)
        (if prefix
            (setq name
                  (cond
                   ((string-match "^self\." name)
                    (concat (substring prefix 0 -1) (substring name 4)))
                  (t (concat prefix name)))))
        (push (cons name pos) index-alist)
        (crystal-accurate-end-of-block end))
       (t
        (if (string= "self" name)
            (if prefix (setq name (substring prefix 0 -1)))
          (if prefix (setq name (concat (substring prefix 0 -1) "::" name)))
          (push (cons name pos) index-alist))
        (crystal-accurate-end-of-block end)
        (setq beg (point))
        (setq index-alist
              (nconc (crystal-imenu-create-index-in-block
                      (concat name (if sing "." "#"))
                      next beg) index-alist))
        (goto-char beg))))
    index-alist))


(defun crystal-imenu-create-index ()
  "Create an imenu index of all methods in the buffer."
  (nreverse (crystal-imenu-create-index-in-block nil (point-min) nil)))

(defun crystal-accurate-end-of-block (&optional end)
  "Jump to the end of the current block or END, whichever is closer."
  (let (state
        (end (or end (point-max))))
    (if crystal-use-smie
        (save-restriction
          (back-to-indentation)
          (narrow-to-region (point) end)
          (smie-forward-sexp))
      (while (and (setq state (apply 'crystal-parse-partial end state))
                    (>= (nth 2 state) 0) (< (point) end))))))

(defun crystal-mode-variables ()
  "Set up initial buffer-local variables for Crystal mode."
  (setq indent-tabs-mode crystal-indent-tabs-mode)
  (if crystal-use-smie
      (smie-setup crystal-smie-grammar #'crystal-smie-rules
                  :forward-token  #'crystal-smie--forward-token
                  :backward-token #'crystal-smie--backward-token)
    (setq-local indent-line-function 'crystal-indent-line))
  (setq-local comment-start "# ")
  (setq-local comment-end "")
  (setq-local comment-column crystal-comment-column)
  (setq-local comment-start-skip "#+ *")
  (setq-local parse-sexp-ignore-comments t)
  (setq-local parse-sexp-lookup-properties t)
  (setq-local paragraph-start (concat "$\\|" page-delimiter))
  (setq-local paragraph-separate paragraph-start)
  (setq-local paragraph-ignore-fill-prefix t))

(defun crystal--insert-coding-comment (encoding)
  "Insert a magic coding comment for ENCODING.
The style of the comment is controlled by `crystal-encoding-magic-comment-style'."
  (let ((encoding-magic-comment-template
         (pcase crystal-encoding-magic-comment-style
           (`crystal "# coding: %s")
           (`emacs "# -*- coding: %s -*-")
           (`custom
            crystal-custom-encoding-magic-comment-template))))
    (insert
     (format encoding-magic-comment-template encoding)
     "\n")))

(defun crystal--detect-encoding ()
  (if (eq crystal-insert-encoding-magic-comment 'always-utf8)
      "utf-8"
    (let ((coding-system
           (or save-buffer-coding-system
               buffer-file-coding-system)))
      (if coding-system
          (setq coding-system
                (or (coding-system-get coding-system 'mime-charset)
                    (coding-system-change-eol-conversion coding-system nil))))
      (if coding-system
          (symbol-name
           (if crystal-use-encoding-map
               (let ((elt (assq coding-system crystal-encoding-map)))
                 (if elt (cdr elt) coding-system))
             coding-system))
        "ascii-8bit"))))

(defun crystal--encoding-comment-required-p ()
  (or (eq crystal-insert-encoding-magic-comment 'always-utf8)
      (re-search-forward "[^\0-\177]" nil t)))

(defun crystal-mode-set-encoding ()
  "Insert a magic comment header with the proper encoding if necessary."
  (save-excursion
    (widen)
    (goto-char (point-min))
    (when (crystal--encoding-comment-required-p)
      (goto-char (point-min))
      (let ((coding-system (crystal--detect-encoding)))
        (when coding-system
          (if (looking-at "^#!") (beginning-of-line 2))
          (cond ((looking-at "\\s *#\\s *.*\\(en\\)?coding\\s *:\\s *\\([-a-z0-9_]*\\)")
                 ;; update existing encoding comment if necessary
                 (unless (string= (match-string 2) coding-system)
                   (goto-char (match-beginning 2))
                   (delete-region (point) (match-end 2))
                   (insert coding-system)))
                ((looking-at "\\s *#.*coding\\s *[:=]"))
                (t (when crystal-insert-encoding-magic-comment
                     (crystal--insert-coding-comment coding-system))))
          (when (buffer-modified-p)
            (basic-save-buffer-1)))))))

(defvar crystal--electric-indent-chars '(?. ?\) ?} ?\]))

(defun crystal--electric-indent-p (char)
  (cond
   ((memq char crystal--electric-indent-chars)
    ;; Reindent after typing a char affecting indentation.
    (crystal--at-indentation-p (1- (point))))
   ((memq (char-after) crystal--electric-indent-chars)
    ;; Reindent after inserting something in front of the above.
    (crystal--at-indentation-p (1- (point))))
   ((or (and (>= char ?a) (<= char ?z)) (memq char '(?_ ?? ?! ?:)))
    (let ((pt (point)))
      (save-excursion
        (skip-chars-backward "[:alpha:]:_?!")
        (and (crystal--at-indentation-p)
             (looking-at (regexp-opt (cons "end" crystal-block-mid-keywords)))
             ;; Outdent after typing a keyword.
             (or (eq (match-end 0) pt)
                 ;; Reindent if it wasn't a keyword after all.
                 (eq (match-end 0) (1- pt)))))))))

;; FIXME: Remove this?  It's unused here, but some redefinitions of
;; `crystal-calculate-indent' in user init files still call it.
(defun crystal-current-indentation ()
  "Return the indentation level of current line."
  (save-excursion
    (beginning-of-line)
    (back-to-indentation)
    (current-column)))

(defun crystal-indent-line (&optional ignored)
  "Correct the indentation of the current Crystal line."
  (interactive)
  (crystal-indent-to (crystal-calculate-indent)))

(defun crystal-indent-to (column)
  "Indent the current line to COLUMN."
  (when column
    (let (shift top beg)
      (and (< column 0) (error "Invalid nesting"))
      (setq shift (current-column))
      (beginning-of-line)
      (setq beg (point))
      (back-to-indentation)
      (setq top (current-column))
      (skip-chars-backward " \t")
      (if (>= shift top) (setq shift (- shift top))
        (setq shift 0))
      (if (and (bolp)
               (= column top))
          (move-to-column (+ column shift))
        (move-to-column top)
        (delete-region beg (point))
        (beginning-of-line)
        (indent-to column)
        (move-to-column (+ column shift))))))

(defun crystal-special-char-p (&optional pos)
  "Return t if the character before POS is a special character.
If omitted, POS defaults to the current point.
Special characters are `?', `$', `:' when preceded by whitespace,
and `\\' when preceded by `?'."
  (setq pos (or pos (point)))
  (let ((c (char-before pos)) (b (and (< (point-min) pos)
				      (char-before (1- pos)))))
    (cond ((or (eq c ??) (eq c ?$)))
          ((and (eq c ?:) (or (not b) (eq (char-syntax b) ? ))))
          ((eq c ?\\) (eq b ??)))))

(defun crystal-singleton-class-p (&optional pos)
  (save-excursion
    (when pos (goto-char pos))
    (forward-word -1)
    (and (or (bolp) (not (eq (char-before (point)) ?_)))
         (looking-at crystal-singleton-class-re))))

(defun crystal-expr-beg (&optional option)
  "Check if point is possibly at the beginning of an expression.
OPTION specifies the type of the expression.
Can be one of `heredoc', `modifier', `expr-qstr', `expr-re'. `macro-cmd'"
  (save-excursion
    (store-match-data nil)
    (let ((space (skip-chars-backward " \t"))
          (start (point)))
      (cond
       ((bolp) t)
       ((progn
          (forward-char -1)
          (and (looking-at "\\?")
               (or (eq (char-syntax (char-before (point))) ?w)
                   (crystal-special-char-p))))
        nil)
       ((looking-at crystal-operator-re))
       ((eq option 'heredoc)
        (and (< space 0) (not (crystal-singleton-class-p start))))
       ((or (looking-at "[\\[({,;]")
            (and (looking-at "[!?]")
                 (or (not (eq option 'modifier))
                     (bolp)
                     (save-excursion (forward-char -1) (looking-at "\\Sw$"))))
            (and (looking-at crystal-symbol-re)
                 (skip-chars-backward crystal-symbol-chars)
                 (cond
                  ((looking-at (regexp-opt
                                (append crystal-block-beg-keywords
                                        crystal-block-op-keywords
                                        crystal-block-mid-keywords)
                                'words))
                   (goto-char (match-end 0))
                   (not (looking-at "\\s_")))
                  ((eq option 'expr-qstr)
                   (looking-at "[a-zA-Z][a-zA-z0-9_]* +%[^ \t}]"))
                  ((eq option 'expr-re)
                   (looking-at "[a-zA-Z][a-zA-z0-9_]* +/[^ \t]"))
                  ((eq option 'macro-cmd)
                   (looking-at "{%"))
                  ((eq option 'macro-var)
                   (looking-at "{{"))
                  (t nil)))))))))

(defun crystal-forward-string (term &optional end no-error expand)
  "Move forward across one balanced pair of string delimiters.
Skips escaped delimiters. If EXPAND is non-nil, also ignores
delimiters in interpolated strings.

TERM should be a string containing either a single, self-matching
delimiter (e.g. \"/\"), or a pair of matching delimiters with the
close delimiter first (e.g. \"][\").

When non-nil, search is bounded by position END.

Throws an error if a balanced match is not found, unless NO-ERROR
is non-nil, in which case nil will be returned.

This command assumes the character after point is an opening
delimiter."
  (let ((n 1) (c (string-to-char term))
        (re (concat "[^\\]\\(\\\\\\\\\\)*\\("
                    (if (string= term "^") ;[^] is not a valid regexp
                        "\\^"
                      (concat "[" term "]"))
                    (when expand "\\|\\(#{\\)")
                    "\\)")))
    (while (and (re-search-forward re end no-error)
                (if (match-beginning 3)
                    (crystal-forward-string "}{" end no-error nil)
                  (> (setq n (if (eq (char-before (point)) c)
                                     (1- n) (1+ n))) 0)))
      (forward-char -1))
    (cond ((zerop n))
          (no-error nil)
          ((error "Unterminated string")))))

(defun crystal-deep-indent-paren-p (c)
  "TODO: document."
  (cond ((listp crystal-deep-indent-paren)
         (let ((deep (assoc c crystal-deep-indent-paren)))
           (cond (deep
                  (or (cdr deep) crystal-deep-indent-paren-style))
                 ((memq c crystal-deep-indent-paren)
                  crystal-deep-indent-paren-style))))
        ((eq c crystal-deep-indent-paren) crystal-deep-indent-paren-style)
        ((eq c ?\( ) crystal-deep-arglist)))

(defun crystal-parse-partial (&optional end in-string nest depth pcol indent)
  "TODO: document throughout function body."
  (or depth (setq depth 0))
  (or indent (setq indent 0))
  (when (re-search-forward crystal-delimiter end 'move)
    (let ((pnt (point)) w re expand)
      (goto-char (match-beginning 0))
      (cond
       ((and (memq (char-before) '(?@ ?$)) (looking-at "\\sw"))
        (goto-char pnt))
       ((looking-at "[\"`]")            ;skip string
        (cond
         ((and (not (eobp))
               (crystal-forward-string (buffer-substring (point) (1+ (point)))
                                    end t t))
          nil)
         (t
          (setq in-string (point))
          (goto-char end))))
       ((looking-at "'")
        (cond
         ((and (not (eobp))
               (re-search-forward "[^\\]\\(\\\\\\\\\\)*'" end t))
          nil)
         (t
          (setq in-string (point))
          (goto-char end))))
       ((looking-at "/=")
        (goto-char pnt))
       ((looking-at "/")
        (cond
         ((and (not (eobp)) (crystal-expr-beg 'expr-re))
          (if (crystal-forward-string "/" end t t)
              nil
            (setq in-string (point))
            (goto-char end)))
         (t
          (goto-char pnt))))
       ((looking-at "%")
        (cond
         ((and (not (eobp))
               (crystal-expr-beg 'expr-qstr)
               (not (looking-at "%="))
               (not (looking-at "%}"))
               (looking-at "%[QqrxWw]?\\([^a-zA-Z0-9 \t\n{]\\)"))
          (goto-char (match-beginning 1))
          (setq expand (not (memq (char-before) '(?q ?w))))
          (setq w (match-string 1))
          (cond
           ((string= w "[") (setq re "]["))
           ((string= w "{") (setq re "}{"))
           ((string= w "(") (setq re ")("))
           ((string= w "<") (setq re "><"))
           ((and expand (string= w "\\"))
            (setq w (concat "\\" w))))
          (unless (cond (re (crystal-forward-string re end t expand))
                        (expand (crystal-forward-string w end t t))
                        (t (re-search-forward
                            (if (string= w "\\")
                                "\\\\[^\\]*\\\\"
                              (concat "[^\\]\\(\\\\\\\\\\)*" w))
                            end t)))
            (setq in-string (point))
            (goto-char end)))
         (t
          (goto-char pnt))))
       ((looking-at "\\?")              ;skip ?char
        (cond
         ((and (crystal-expr-beg)
               (looking-at "?\\(\\\\C-\\|\\\\M-\\)*\\\\?."))
          (goto-char (match-end 0)))
         (t
          (goto-char pnt))))
       ((looking-at "\\$")              ;skip $char
        (goto-char pnt)
        (forward-char 1))
       ((looking-at "#")                ;skip comment
        (forward-line 1)
        (goto-char (point))
        )
       ((looking-at "[\\[{(]")
        (let ((deep (crystal-deep-indent-paren-p (char-after))))
          (if (and deep (or (not (eq (char-after) ?\{)) (crystal-expr-beg)))
              (progn
                (and (eq deep 'space) (looking-at ".\\s +[^# \t\n]")
                     (setq pnt (1- (match-end 0))))
                (setq nest (cons (cons (char-after (point)) pnt) nest))
                (setq pcol (cons (cons pnt depth) pcol))
                (setq depth 0))
            (setq nest (cons (cons (char-after (point)) pnt) nest))
            (setq depth (1+ depth))))
        (goto-char pnt)
        )
       ((looking-at "[])}]")
        (if (crystal-deep-indent-paren-p (matching-paren (char-after)))
            (setq depth (cdr (car pcol)) pcol (cdr pcol))
          (setq depth (1- depth)))
        (setq nest (cdr nest))
        (goto-char pnt))
       ((looking-at crystal-block-end-re)
        (if (or (and (not (bolp))
                     (progn
                       (forward-char -1)
                       (setq w (char-after (point)))
                       (or (eq ?_ w)
                           (eq ?. w))))
                (progn
                  (goto-char pnt)
                  (setq w (char-after (point)))
                  (or (eq ?_ w)
                      (eq ?! w)
                      (eq ?? w))))
            nil
          (setq nest (cdr nest))
          (setq depth (1- depth)))
        (goto-char pnt))
       ((looking-at "def\\s +[^(\n;]*")
        (if (or (bolp)
                (progn
                  (forward-char -1)
                  (not (eq ?_ (char-after (point))))))
            (progn
              (setq nest (cons (cons nil pnt) nest))
              (setq depth (1+ depth))))
        (goto-char (match-end 0)))
       ((looking-at (concat "\\_<\\(" crystal-block-beg-re "\\)\\_>"))
        (and
         (save-match-data
           (or (not (looking-at "do\\_>"))
               (save-excursion
                 (back-to-indentation)
                 (not (looking-at crystal-non-block-do-re)))))
         (or (bolp)
             (progn
               (forward-char -1)
               (setq w (char-after (point)))
               (not (or (eq ?_ w)
                        (eq ?. w)))))
         (goto-char pnt)
         (not (eq ?! (char-after (point))))
         (skip-chars-forward " \t")
         (goto-char (match-beginning 0))
         (or (not (looking-at crystal-modifier-re))
             (crystal-expr-beg 'modifier))
         (goto-char pnt)
         (setq nest (cons (cons nil pnt) nest))
         (setq depth (1+ depth)))
        (goto-char pnt))
       ((looking-at ":\\(['\"]\\)")
        (goto-char (match-beginning 1))
        (crystal-forward-string (match-string 1) end t))
       ((looking-at ":\\([-,.+*/%&|^~<>]=?\\|===?\\|<=>\\|![~=]?\\)")
        (goto-char (match-end 0)))
       ((looking-at ":\\([a-zA-Z_][a-zA-Z_0-9]*[!?=]?\\)?")
        (goto-char (match-end 0)))
       ((or (looking-at "\\.\\.\\.?")
            (looking-at "\\.[0-9]+")
            (looking-at "\\.[a-zA-Z_0-9]+")
            (looking-at "\\."))
        (goto-char (match-end 0)))
       ((looking-at "^=begin")
        (if (re-search-forward "^=end" end t)
            (forward-line 1)
          (setq in-string (match-end 0))
          (goto-char end)))
       ((looking-at "<<")
        (cond
         ((and (crystal-expr-beg 'heredoc)
               (looking-at "<<\\(-\\)?\\(\\([\"'`]\\)\\([^\n]+?\\)\\3\\|\\(?:\\sw\\|\\s_\\)+\\)"))
          (setq re (regexp-quote (or (match-string 4) (match-string 2))))
          (if (match-beginning 1) (setq re (concat "\\s *" re)))
          (let* ((id-end (goto-char (match-end 0)))
                 (line-end-position (point-at-eol))
                 (state (list in-string nest depth pcol indent)))
            ;; parse the rest of the line
            (while (and (> line-end-position (point))
                        (setq state (apply 'crystal-parse-partial
                                           line-end-position state))))
            (setq in-string (car state)
                  nest (nth 1 state)
                  depth (nth 2 state)
                  pcol (nth 3 state)
                  indent (nth 4 state))
            ;; skip heredoc section
            (if (re-search-forward (concat "^" re "$") end 'move)
                (forward-line 1)
              (setq in-string id-end)
              (goto-char end))))
         (t
          (goto-char pnt))))
       ((looking-at "^__END__$")
        (goto-char pnt))
       ((and (looking-at crystal-here-doc-beg-re)
	     (boundp 'crystal-indent-point))
        (if (re-search-forward (crystal-here-doc-end-match)
                               crystal-indent-point t)
            (forward-line 1)
          (setq in-string (match-end 0))
          (goto-char crystal-indent-point)))
       (t
        (error (format "Bad string %s"
                       (buffer-substring (point) pnt)
                       ))))))
  (list in-string nest depth pcol))

(defun crystal-parse-region (start end)
  "TODO: document."
  (let (state)
    (save-excursion
      (if start
          (goto-char start)
        (crystal-beginning-of-indent))
      (save-restriction
        (narrow-to-region (point) end)
        (while (and (> end (point))
                    (setq state (apply 'crystal-parse-partial end state))))))
    (list (nth 0 state)                 ; in-string
          (car (nth 1 state))           ; nest
          (nth 2 state)                 ; depth
          (car (car (nth 3 state)))     ; pcol
          ;(car (nth 5 state))          ; indent
          )))

(defun crystal-indent-size (pos nest)
  "Return the indentation level in spaces NEST levels deeper than POS."
  (+ pos (* (or nest 1) crystal-indent-level)))

(defun crystal-calculate-indent (&optional parse-start)
  "Return the proper indentation level of the current line."
  ;; TODO: Document body
  (save-excursion
    (beginning-of-line)
    (let ((crystal-indent-point (point))
          (case-fold-search nil)
          state eol begin op-end
          (paren (progn (skip-syntax-forward " ")
                        (and (char-after) (matching-paren (char-after)))))
          (indent 0))
      (if parse-start
          (goto-char parse-start)
        (crystal-beginning-of-indent)
        (setq parse-start (point)))
      (back-to-indentation)
      (setq indent (current-column))
      (setq state (crystal-parse-region parse-start crystal-indent-point))
      (cond
       ((nth 0 state)                   ; within string
        (setq indent nil))              ;  do nothing
       ((car (nth 1 state))             ; in paren
        (goto-char (setq begin (cdr (nth 1 state))))
        (let ((deep (crystal-deep-indent-paren-p (car (nth 1 state)))))
          (if deep
              (cond ((and (eq deep t) (eq (car (nth 1 state)) paren))
                     (skip-syntax-backward " ")
                     (setq indent (1- (current-column))))
                    ((let ((s (crystal-parse-region (point) crystal-indent-point)))
                       (and (nth 2 s) (> (nth 2 s) 0)
                            (or (goto-char (cdr (nth 1 s))) t)))
                     (forward-word -1)
                     (setq indent (crystal-indent-size (current-column)
						    (nth 2 state))))
                    (t
                     (setq indent (current-column))
                     (cond ((eq deep 'space))
                           (paren (setq indent (1- indent)))
                           (t (setq indent (crystal-indent-size (1- indent) 1))))))
            (if (nth 3 state) (goto-char (nth 3 state))
              (goto-char parse-start) (back-to-indentation))
            (setq indent (crystal-indent-size (current-column) (nth 2 state))))
          (and (eq (car (nth 1 state)) paren)
               (crystal-deep-indent-paren-p (matching-paren paren))
               (search-backward (char-to-string paren))
               (setq indent (current-column)))))
       ((and (nth 2 state) (> (nth 2 state) 0)) ; in nest
        (if (null (cdr (nth 1 state)))
            (error "Invalid nesting"))
        (goto-char (cdr (nth 1 state)))
        (forward-word -1)               ; skip back a keyword
        (setq begin (point))
        (cond
         ((looking-at "do\\>[^_]")      ; iter block is a special case
          (if (nth 3 state) (goto-char (nth 3 state))
            (goto-char parse-start) (back-to-indentation))
          (setq indent (crystal-indent-size (current-column) (nth 2 state))))
         (t
          (setq indent (+ (current-column) crystal-indent-level)))))

       ((and (nth 2 state) (< (nth 2 state) 0)) ; in negative nest
        (setq indent (crystal-indent-size (current-column) (nth 2 state)))))
      (when indent
        (goto-char crystal-indent-point)
        (end-of-line)
        (setq eol (point))
        (beginning-of-line)
        (cond
         ((and (not (crystal-deep-indent-paren-p paren))
               (re-search-forward crystal-negative eol t))
          (and (not (eq ?_ (char-after (match-end 0))))
               (setq indent (- indent crystal-indent-level))))
         ((and
           (save-excursion
             (beginning-of-line)
             (not (bobp)))
           (or (crystal-deep-indent-paren-p t)
               (null (car (nth 1 state)))))
          ;; goto beginning of non-empty no-comment line
          (let (end done)
            (while (not done)
              (skip-chars-backward " \t\n")
              (setq end (point))
              (beginning-of-line)
              (if (re-search-forward "^\\s *#" end t)
                  (beginning-of-line)
                (setq done t))))
          (end-of-line)
          ;; skip the comment at the end
          (skip-chars-backward " \t")
          (let (end (pos (point)))
            (beginning-of-line)
            (while (and (re-search-forward "#" pos t)
                        (setq end (1- (point)))
                        (or (crystal-special-char-p end)
                            (and (setq state (crystal-parse-region
                                              parse-start end))
                                 (nth 0 state))))
              (setq end nil))
            (goto-char (or end pos))
            (skip-chars-backward " \t")
            (setq begin (if (and end (nth 0 state)) pos (cdr (nth 1 state))))
            (setq state (crystal-parse-region parse-start (point))))
          (or (bobp) (forward-char -1))
          (and
           (or (and (looking-at crystal-symbol-re)
                    (skip-chars-backward crystal-symbol-chars)
                    (looking-at (concat "\\<\\(" crystal-block-hanging-re
                                        "\\)\\>"))
                    (not (eq (point) (nth 3 state)))
                    (save-excursion
                      (goto-char (match-end 0))
                      (not (looking-at "[a-z_]"))))
               (and (looking-at crystal-operator-re)
                    (not (crystal-special-char-p))
                    (save-excursion
                      (forward-char -1)
                      (or (not (looking-at crystal-operator-re))
                          (not (eq (char-before) ?:))))
                    ;; Operator at the end of line.
                    (let ((c (char-after (point))))
                      (and
;;                     (or (null begin)
;;                         (save-excursion
;;                           (goto-char begin)
;;                           (skip-chars-forward " \t")
;;                           (not (or (eolp) (looking-at "#")
;;                                    (and (eq (car (nth 1 state)) ?{)
;;                                         (looking-at "|"))))))
                       ;; Not a regexp or percent literal.
                       (null (nth 0 (crystal-parse-region (or begin parse-start)
                                                       (point))))
                       (or (not (eq ?| (char-after (point))))
                           (save-excursion
                             (or (eolp) (forward-char -1))
                             (cond
                              ((search-backward "|" nil t)
                               (skip-chars-backward " \t\n")
                               (and (not (eolp))
                                    (progn
                                      (forward-char -1)
                                      (not (looking-at "{")))
                                    (progn
                                      (forward-word -1)
                                      (not (looking-at "do\\>[^_]")))))
                              (t t))))
                       (not (eq ?, c))
                       (setq op-end t)))))
           (setq indent
                 (cond
                  ((and
                    (null op-end)
                    (not (looking-at (concat "\\<\\(" crystal-block-hanging-re
                                             "\\)\\>")))
                    (eq (crystal-deep-indent-paren-p t) 'space)
                    (not (bobp)))
                   (widen)
                   (goto-char (or begin parse-start))
                   (skip-syntax-forward " ")
                   (current-column))
                  ((car (nth 1 state)) indent)
                  (t
                   (+ indent crystal-indent-level))))))))
      (goto-char crystal-indent-point)
      (beginning-of-line)
      (skip-syntax-forward " ")
      (if (looking-at "\\.[^.]")
          (+ indent crystal-indent-level)
        indent))))

(defun crystal-beginning-of-defun (&optional arg)
  "Move backward to the beginning of the current defun.
With ARG, move backward multiple defuns.  Negative ARG means
move forward."
  (interactive "p")
  (let (case-fold-search)
    (and (re-search-backward (concat "^\\s *" crystal-defun-beg-re "\\_>")
                             nil t (or arg 1))
         (beginning-of-line))))

(defun crystal-end-of-defun ()
  "Move point to the end of the current defun.
The defun begins at or after the point.  This function is called
by `end-of-defun'."
  (interactive "p")
  (crystal-forward-sexp)
  (let (case-fold-search)
    (when (looking-back (concat "^\\s *" crystal-block-end-re))
      (forward-line 1))))

(defun crystal-beginning-of-indent ()
  "Backtrack to a line which can be used as a reference for
calculating indentation on the lines after it."
  (while (and (re-search-backward crystal-indent-beg-re nil 'move)
              (if (crystal-in-ppss-context-p 'anything)
                  t
                ;; We can stop, then.
                (beginning-of-line)))))


(defun crystal-move-to-block (n)
  "Move to the beginning (N < 0) or the end (N > 0) of the
current block, a sibling block, or an outer block.  Do that (abs N) times."
  (back-to-indentation)
  (let ((signum (if (> n 0) 1 -1))
        (backward (< n 0))
        (depth (or (nth 2 (crystal-parse-region (point) (line-end-position))) 0))
        case-fold-search
        down done)
    (when (looking-at crystal-block-mid-re)
      (setq depth (+ depth signum)))
    (when (< (* depth signum) 0)
      ;; Moving end -> end or beginning -> beginning.
      (setq depth 0))
    (dotimes (_ (abs n))
      (setq done nil)
      (setq down (save-excursion
                   (back-to-indentation)
                   ;; There is a block start or block end keyword on this
                   ;; line, don't need to look for another block.
                   (and (re-search-forward
                         (if backward crystal-block-end-re
                           (concat "\\_<\\(" crystal-block-beg-re "\\)\\_>"))
                         (line-end-position) t)
                        (not (nth 8 (syntax-ppss))))))
      (while (and (not done) (not (if backward (bobp) (eobp))))
        (forward-line signum)
        (cond
         ;; Skip empty and commented out lines.
         ((looking-at "^\\s *$"))
         ((looking-at "^\\s *#"))
         ;; Skip block comments;
         ((and (not backward) (looking-at "^=begin\\>"))
          (re-search-forward "^=end\\>"))
         ((and backward (looking-at "^=end\\>"))
          (re-search-backward "^=begin\\>"))
         ;; Jump over a multiline literal.
         ((crystal-in-ppss-context-p 'string)
          (goto-char (nth 8 (syntax-ppss)))
          (unless backward
            (forward-sexp)
            (when (bolp) (forward-char -1)))) ; After a heredoc.
         (t
          (let ((state (crystal-parse-region (point) (line-end-position))))
            (unless (car state) ; Line ends with unfinished string.
              (setq depth (+ (nth 2 state) depth))))
          (cond
           ;; Increased depth, we found a block.
           ((> (* signum depth) 0)
            (setq down t))
           ;; We're at the same depth as when we started, and we've
           ;; encountered a block before.  Stop.
           ((and down (zerop depth))
            (setq done t))
           ;; Lower depth, means outer block, can stop now.
           ((< (* signum depth) 0)
            (setq done t)))))))
    (back-to-indentation)))

(defun crystal-beginning-of-block (&optional arg)
  "Move backward to the beginning of the current block.
With ARG, move up multiple blocks."
  (interactive "p")
  (crystal-move-to-block (- (or arg 1))))

(defun crystal-end-of-block (&optional arg)
  "Move forward to the end of the current block.
With ARG, move out of multiple blocks."
  (interactive "p")
  (crystal-move-to-block (or arg 1)))

(defun crystal-forward-sexp (&optional arg)
  "Move forward across one balanced expression (sexp).
With ARG, do it many times.  Negative ARG means move backward."
  ;; TODO: Document body
  (interactive "p")
  (cond
   (crystal-use-smie (forward-sexp arg))
   ((and (numberp arg) (< arg 0)) (crystal-backward-sexp (- arg)))
   (t
    (let ((i (or arg 1)))
      (condition-case nil
          (while (> i 0)
            (skip-syntax-forward " ")
	    (if (looking-at ",\\s *") (goto-char (match-end 0)))
            (cond ((looking-at "\\?\\(\\\\[CM]-\\)*\\\\?\\S ")
                   (goto-char (match-end 0)))
                  ((progn
                     (skip-chars-forward ",.:;|&^~=!?\\+\\-\\*")
                     (looking-at "\\s("))
                   (goto-char (scan-sexps (point) 1)))
                  ((and (looking-at (concat "\\<\\(" crystal-block-beg-re
                                            "\\)\\>"))
                        (not (eq (char-before (point)) ?.))
                        (not (eq (char-before (point)) ?:)))
                   (crystal-end-of-block)
                   (forward-word 1))
                  ((looking-at "\\(\\$\\|@@?\\)?\\sw")
                   (while (progn
                            (while (progn (forward-word 1) (looking-at "_")))
                            (cond ((looking-at "::") (forward-char 2) t)
                                  ((> (skip-chars-forward ".") 0))
                                  ((looking-at "\\?\\|!\\(=[~=>]\\|[^~=]\\)")
                                   (forward-char 1) nil)))))
                  ((let (state expr)
                     (while
                         (progn
                           (setq expr (or expr (crystal-expr-beg)
                                          (looking-at "%\\sw?\\Sw\\|[\"'`/]")))
                           (nth 1 (setq state (apply #'crystal-parse-partial
                                                     nil state))))
                       (setq expr t)
                       (skip-chars-forward "<"))
                     (not expr))))
            (setq i (1- i)))
        ((error) (forward-word 1)))
      i))))

(defun crystal-backward-sexp (&optional arg)
  "Move backward across one balanced expression (sexp).
With ARG, do it many times.  Negative ARG means move forward."
  ;; TODO: Document body
  (interactive "p")
  (cond
   (crystal-use-smie (backward-sexp arg))
   ((and (numberp arg) (< arg 0)) (crystal-forward-sexp (- arg)))
   (t
    (let ((i (or arg 1)))
      (condition-case nil
          (while (> i 0)
            (skip-chars-backward " \t\n,.:;|&^~=!?\\+\\-\\*")
            (forward-char -1)
            (cond ((looking-at "\\s)")
                   (goto-char (scan-sexps (1+ (point)) -1))
                   (pcase (char-before)
                     (`?% (forward-char -1))
                     ((or `?q `?Q `?w `?W `?r `?x)
                      (if (eq (char-before (1- (point))) ?%)
                          (forward-char -2))))
                   nil)
                  ((looking-at "\\s\"\\|\\\\\\S_")
                   (let ((c (char-to-string (char-before (match-end 0)))))
                     (while (and (search-backward c)
				 (eq (logand (skip-chars-backward "\\") 1)
				     1))))
                   nil)
                  ((looking-at "\\s.\\|\\s\\")
                   (if (crystal-special-char-p) (forward-char -1)))
                  ((looking-at "\\s(") nil)
                  (t
                   (forward-char 1)
                   (while (progn (forward-word -1)
                                 (pcase (char-before)
                                   (`?_ t)
                                   (`?. (forward-char -1) t)
                                   ((or `?$ `?@)
                                    (forward-char -1)
                                    (and (eq (char-before) (char-after))
                                         (forward-char -1)))
                                   (`?:
                                    (forward-char -1)
                                    (eq (char-before) :)))))
                   (if (looking-at crystal-block-end-re)
                       (crystal-beginning-of-block))
                   nil))
            (setq i (1- i)))
        ((error)))
      i))))

(defun crystal-indent-exp (&optional ignored)
  "Indent each line in the balanced expression following the point."
  (interactive "*P")
  (let ((here (point-marker)) start top column (nest t))
    (set-marker-insertion-type here t)
    (unwind-protect
        (progn
          (beginning-of-line)
          (setq start (point) top (current-indentation))
          (while (and (not (eobp))
                      (progn
                        (setq column (crystal-calculate-indent start))
                        (cond ((> column top)
                               (setq nest t))
                              ((and (= column top) nest)
                               (setq nest nil) t))))
            (crystal-indent-to column)
            (beginning-of-line 2)))
      (goto-char here)
      (set-marker here nil))))

(defun crystal-add-log-current-method ()
  "Return the current method name as a string.
This string includes all namespaces.

For example:

  #exit
  String#gsub
  Net::HTTP#active?
  File.open

See `add-log-current-defun-function'."
  (condition-case nil
      (save-excursion
        (let* ((indent 0) mname mlist
               (start (point))
               (make-definition-re
                (lambda (re)
                  (concat "^[ \t]*" re "[ \t]+"
                          "\\("
                          ;; \\. and :: for class methods
                          "\\([A-Za-z_]" crystal-symbol-re "*\\|\\.\\|::" "\\)"
                          "+\\)")))
               (definition-re (funcall make-definition-re crystal-defun-beg-re))
               (module-re (funcall make-definition-re "\\(class\\|module\\)")))
          ;; Get the current method definition (or class/module).
          (when (re-search-backward definition-re nil t)
            (goto-char (match-beginning 1))
            (if (not (string-equal "def" (match-string 1)))
                (setq mlist (list (match-string 2)))
              ;; We're inside the method. For classes and modules,
              ;; this check is skipped for performance.
              (when (crystal-block-contains-point start)
                (setq mname (match-string 2))))
            (setq indent (current-column))
            (beginning-of-line))
          ;; Walk up the class/module nesting.
          (while (and (> indent 0)
                      (re-search-backward module-re nil t))
            (goto-char (match-beginning 1))
            (when (< (current-column) indent)
              (setq mlist (cons (match-string 2) mlist))
              (setq indent (current-column))
              (beginning-of-line)))
          ;; Process the method name.
          (when mname
            (let ((mn (split-string mname "\\.\\|::")))
              (if (cdr mn)
                  (progn
                    (unless (string-equal "self" (car mn)) ; def self.foo
                      ;; def C.foo
                      (let ((ml (nreverse mlist)))
                        ;; If the method name references one of the
                        ;; containing modules, drop the more nested ones.
                        (while ml
                          (if (string-equal (car ml) (car mn))
                              (setq mlist (nreverse (cdr ml)) ml nil))
                          (or (setq ml (cdr ml)) (nreverse mlist))))
                      (if mlist
                          (setcdr (last mlist) (butlast mn))
                        (setq mlist (butlast mn))))
                    (setq mname (concat "." (car (last mn)))))
                ;; See if the method is in singleton class context.
                (let ((in-singleton-class
                       (when (re-search-forward crystal-singleton-class-re start t)
                         (goto-char (match-beginning 0))
                         ;; FIXME: Optimize it out, too?
                         ;; This can be slow in a large file, but
                         ;; unlike class/module declaration
                         ;; indentations, method definitions can be
                         ;; intermixed with these, and may or may not
                         ;; be additionally indented after visibility
                         ;; keywords.
                         (crystal-block-contains-point start))))
                  (setq mname (concat
                               (if in-singleton-class "." "#")
                               mname))))))
          ;; Generate the string.
          (if (consp mlist)
              (setq mlist (mapconcat (function identity) mlist "::")))
          (if mname
              (if mlist (concat mlist mname) mname)
            mlist)))))

(defun crystal-block-contains-point (pt)
  (save-excursion
    (save-match-data
      (crystal-forward-sexp)
      (> (point) pt))))

(defun crystal-brace-to-do-end (orig end)
  (let (beg-marker end-marker)
    (goto-char end)
    (when (eq (char-before) ?\})
      (delete-char -1)
      (when (save-excursion
              (skip-chars-backward " \t")
              (not (bolp)))
        (insert "\n"))
      (insert "end")
      (setq end-marker (point-marker))
      (when (and (not (eobp)) (eq (char-syntax (char-after)) ?w))
        (insert " "))
      (goto-char orig)
      (delete-char 1)
      (when (eq (char-syntax (char-before)) ?w)
        (insert " "))
      (insert "do")
      (setq beg-marker (point-marker))
      (when (looking-at "\\(\\s \\)*|")
        (unless (match-beginning 1)
          (insert " "))
        (goto-char (1+ (match-end 0)))
        (search-forward "|"))
      (unless (looking-at "\\s *$")
        (insert "\n"))
      (indent-region beg-marker end-marker)
      (goto-char beg-marker)
      t)))

(defun crystal-do-end-to-brace (orig end)
  (let (beg-marker end-marker beg-pos end-pos)
    (goto-char (- end 3))
    (when (looking-at crystal-block-end-re)
      (delete-char 3)
      (setq end-marker (point-marker))
      (insert "}")
      (goto-char orig)
      (delete-char 2)
      ;; Maybe this should be customizable, let's see if anyone asks.
      (insert "{ ")
      (setq beg-marker (point-marker))
      (when (looking-at "\\s +|")
        (delete-char (- (match-end 0) (match-beginning 0) 1))
        (forward-char)
        (re-search-forward "|" (line-end-position) t))
      (save-excursion
        (skip-chars-forward " \t\n\r")
        (setq beg-pos (point))
        (goto-char end-marker)
        (skip-chars-backward " \t\n\r")
        (setq end-pos (point)))
      (when (or
             (< end-pos beg-pos)
             (and (= (line-number-at-pos beg-pos) (line-number-at-pos end-pos))
                  (< (+ (current-column) (- end-pos beg-pos) 2) fill-column)))
        (just-one-space -1)
        (goto-char end-marker)
        (just-one-space -1))
      (goto-char beg-marker)
      t)))

(defun crystal-toggle-block ()
  "Toggle block type from do-end to braces or back.
The block must begin on the current line or above it and end after the point.
If the result is do-end block, it will always be multiline."
  (interactive)
  (let ((start (point)) beg end)
    (end-of-line)
    (unless
        (if (and (re-search-backward "\\(?:[^#]\\)\\({\\)\\|\\(\\_<do\\_>\\)")
                 (progn
                   (goto-char (or (match-beginning 1) (match-beginning 2)))
                   (setq beg (point))
                   (save-match-data (crystal-forward-sexp))
                   (setq end (point))
                   (> end start)))
            (if (match-beginning 1)
                (crystal-brace-to-do-end beg end)
              (crystal-do-end-to-brace beg end)))
      (goto-char start))))

(defun crystal--string-region ()
  "Return region for string at point."
  (let ((state (syntax-ppss)))
    (when (memq (nth 3 state) '(?' ?\"))
      (save-excursion
        (goto-char (nth 8 state))
        (forward-sexp)
        (list (nth 8 state) (point))))))

(defun crystal-string-at-point-p ()
  "Check if cursor is at a string or not."
  (crystal--string-region))

(defun crystal--inverse-string-quote (string-quote)
  "Get the inverse string quoting for STRING-QUOTE."
  (if (equal string-quote "\"") "'" "\""))

(defun crystal-toggle-string-quotes ()
  "Toggle string literal quoting between single and double."
  (interactive)
  (when (crystal-string-at-point-p)
    (let* ((region (crystal--string-region))
           (min (nth 0 region))
           (max (nth 1 region))
           (string-quote (crystal--inverse-string-quote (buffer-substring-no-properties min (1+ min))))
           (content
            (buffer-substring-no-properties (1+ min) (1- max))))
      (setq content
            (if (equal string-quote "\"")
                (replace-regexp-in-string "\\\\\"" "\"" (replace-regexp-in-string "\\([^\\\\]\\)'" "\\1\\\\'" content))
              (replace-regexp-in-string "\\\\\'" "'" (replace-regexp-in-string "\\([^\\\\]\\)\"" "\\1\\\\\"" content))))
      (let ((orig-point (point)))
        (delete-region min max)
        (insert
         (format "%s%s%s" string-quote content string-quote))
        (goto-char orig-point)))))

(eval-and-compile
  (defconst crystal-percent-literal-beg-re
    "\\(%\\)[qQrswWxIi]?\\([!\"#$%&'()*+,\-./:;<=>?@[\\\]^_`{|~]\\)"
    "Regexp to match the beginning of percent literal.")

  (defconst crystal-syntax-methods-before-regexp
    '("gsub" "gsub!" "sub" "sub!" "scan" "split" "split!" "index" "match"
      "assert_match" "Given" "Then" "When")
    "Methods that can take regexp as the first argument.
It will be properly highlighted even when the call omits parens.")

  (defvar crystal-syntax-before-regexp-re
    (concat
     ;; Special tokens that can't be followed by a division operator.
     "\\(^\\|[[=(,~;<>]"
     ;; Distinguish ternary operator tokens.
     ;; FIXME: They don't really have to be separated with spaces.
     "\\|[?:] "
     ;; Control flow keywords and operators following bol or whitespace.
     "\\|\\(?:^\\|\\s \\)"
     (regexp-opt '("if" "elsif" "unless" "while" "until" "when" "and"
                   "or" "not" "&&" "||"))
     ;; Method name from the list.
     "\\|\\_<"
     (regexp-opt crystal-syntax-methods-before-regexp)
     "\\)\\s *")
    "Regexp to match text that can be followed by a regular expression."))

(defun crystal-syntax-propertize-function (start end)
  "Syntactic keywords for Crystal mode.  See `syntax-propertize-function'."
  (let (case-fold-search)
    (goto-char start)
    (remove-text-properties start end '(crystal-expansion-match-data))
    (crystal-syntax-propertize-heredoc end)
    (crystal-syntax-enclosing-percent-literal end)
    (funcall
     (syntax-propertize-rules
      ;; $' $" $` .... are variables.
      ;; ?' ?" ?` are character literals (one-char strings in 1.9+).
      ("\\([?$]\\)[#\"'`]"
       (1 (if (save-excursion
                (nth 3 (syntax-ppss (match-beginning 0))))
              ;; Within a string, skip.
              (goto-char (match-end 1))
            (string-to-syntax "\\"))))
      ;; Part of symbol when at the end of a method name.
      ("[!?]"
       (0 (unless (save-excursion
                    (or (nth 8 (syntax-ppss (match-beginning 0)))
                        (eq (char-before) ?:)
                        (let (parse-sexp-lookup-properties)
                          (zerop (skip-syntax-backward "w_")))
                        (memq (preceding-char) '(?@ ?$))))
            (string-to-syntax "_"))))
      ;; Regular expressions.  Start with matching unescaped slash.
      ("\\(?:\\=\\|[^\\]\\)\\(?:\\\\\\\\\\)*\\(/\\)"
       (1 (let ((state (save-excursion (syntax-ppss (match-beginning 1)))))
            (when (or
                   ;; Beginning of a regexp.
                   (and (null (nth 8 state))
                        (save-excursion
                          (forward-char -1)
                          (looking-back crystal-syntax-before-regexp-re
                                        (point-at-bol))))
                   ;; End of regexp.  We don't match the whole
                   ;; regexp at once because it can have
                   ;; string interpolation inside, or span
                   ;; several lines.
                   (eq ?/ (nth 3 state)))
              (string-to-syntax "\"/")))))
      ;; Expression expansions in strings.  We're handling them
      ;; here, so that the regexp rule never matches inside them.
      (crystal-expression-expansion-re
       (0 (ignore (crystal-syntax-propertize-expansion))))
      ("^=en\\(d\\)\\_>" (1 "!"))
      ("^\\(=\\)begin\\_>" (1 "!"))
      ;; Handle here documents.
      ((concat crystal-here-doc-beg-re ".*\\(\n\\)")
       (7 (unless (or (nth 8 (save-excursion
                               (syntax-ppss (match-beginning 0))))
                      (crystal-singleton-class-p (match-beginning 0)))
            (put-text-property (match-beginning 7) (match-end 7)
                               'syntax-table (string-to-syntax "\""))
            (crystal-syntax-propertize-heredoc end))))
      ;; Handle percent literals: %w(), %q{}, etc.
      ((concat "\\(?:^\\|[[ \t\n<+(,=]\\)" crystal-percent-literal-beg-re)
       (1 (prog1 "|" (crystal-syntax-propertize-percent-literal end)))))
     (point) end)))

(defun crystal-syntax-propertize-heredoc (limit)
  (let ((ppss (syntax-ppss))
        (res '()))
    (when (eq ?\n (nth 3 ppss))
      (save-excursion
        (goto-char (nth 8 ppss))
        (beginning-of-line)
        (while (re-search-forward crystal-here-doc-beg-re
                                  (line-end-position) t)
          (unless (crystal-singleton-class-p (match-beginning 0))
            (push (concat (crystal-here-doc-end-match) "\n") res))))
      (save-excursion
        ;; With multiple openers on the same line, we don't know in which
        ;; part `start' is, so we have to go back to the beginning.
        (when (cdr res)
          (goto-char (nth 8 ppss))
          (setq res (nreverse res)))
        (while (and res (re-search-forward (pop res) limit 'move))
          (if (null res)
              (put-text-property (1- (point)) (point)
                                 'syntax-table (string-to-syntax "\""))))
        ;; End up at bol following the heredoc openers.
        ;; Propertize expression expansions from this point forward.
        ))))

(defun crystal-syntax-enclosing-percent-literal (limit)
  (let ((state (syntax-ppss))
        (start (point)))
    ;; When already inside percent literal, re-propertize it.
    (when (eq t (nth 3 state))
      (goto-char (nth 8 state))
      (when (looking-at crystal-percent-literal-beg-re)
        (crystal-syntax-propertize-percent-literal limit))
      (when (< (point) start) (goto-char start)))))

(defun crystal-syntax-propertize-percent-literal (limit)
  (goto-char (match-beginning 2))
  ;; Not inside a simple string or comment.
  (when (eq t (nth 3 (syntax-ppss)))
    (let* ((op (char-after))
           (ops (char-to-string op))
           (cl (or (cdr (aref (syntax-table) op))
                   (cdr (assoc op '((?< . ?>))))))
           parse-sexp-lookup-properties)
      (save-excursion
        (condition-case nil
            (progn
              (if cl              ; Paired delimiters.
                  ;; Delimiter pairs of the same kind can be nested
                  ;; inside the literal, as long as they are balanced.
                  ;; Create syntax table that ignores other characters.
                  (with-syntax-table (make-char-table 'syntax-table nil)
                    (modify-syntax-entry op (concat "(" (char-to-string cl)))
                    (modify-syntax-entry cl (concat ")" ops))
                    (modify-syntax-entry ?\\ "\\")
                    (save-restriction
                      (narrow-to-region (point) limit)
                      (forward-list))) ; skip to the paired character
                ;; Single character delimiter.
                (re-search-forward (concat "[^\\]\\(?:\\\\\\\\\\)*"
                                           (regexp-quote ops)) limit nil))
              ;; Found the closing delimiter.
              (put-text-property (1- (point)) (point) 'syntax-table
                                 (string-to-syntax "|")))
          ;; Unclosed literal, do nothing.
          ((scan-error search-failed)))))))

(defun crystal-syntax-propertize-expansion ()
  ;; Save the match data to a text property, for font-locking later.
  ;; Set the syntax of all double quotes and backticks to punctuation.
  (let* ((beg (match-beginning 2))
         (end (match-end 2))
         (state (and beg (save-excursion (syntax-ppss beg)))))
    (when (crystal-syntax-expansion-allowed-p state)
      (put-text-property beg (1+ beg) 'crystal-expansion-match-data
                         (match-data))
      (goto-char beg)
      (while (re-search-forward "[\"`]" end 'move)
        (put-text-property (match-beginning 0) (match-end 0)
                           'syntax-table (string-to-syntax "."))))))

(defun crystal-syntax-expansion-allowed-p (parse-state)
  "Return non-nil if expression expansion is allowed."
  (let ((term (nth 3 parse-state)))
    (cond
     ((memq term '(?\" ?` ?\n ?/)))
     ((eq term t)
      (save-match-data
        (save-excursion
          (goto-char (nth 8 parse-state))
          (looking-at "%\\(?:[QWrxI]\\|\\W\\)")))))))

(defun crystal-syntax-propertize-expansions (start end)
  (save-excursion
    (goto-char start)
    (while (re-search-forward crystal-expression-expansion-re end 'move)
      (crystal-syntax-propertize-expansion))))

(defun crystal-in-ppss-context-p (context &optional ppss)
  (let ((ppss (or ppss (syntax-ppss (point)))))
    (if (cond
         ((eq context 'anything)
          (or (nth 3 ppss)
              (nth 4 ppss)))
         ((eq context 'string)
          (nth 3 ppss))
         ((eq context 'heredoc)
          (eq ?\n (nth 3 ppss)))
         ((eq context 'non-heredoc)
          (and (crystal-in-ppss-context-p 'anything)
               (not (crystal-in-ppss-context-p 'heredoc))))
         ((eq context 'comment)
          (nth 4 ppss))
         (t
          (error (concat
                  "Internal error on `crystal-in-ppss-context-p': "
                  "context name `" (symbol-name context) "' is unknown"))))
        t)))

(defvar crystal-font-lock-syntax-table
  (let ((tbl (copy-syntax-table crystal-mode-syntax-table)))
    (modify-syntax-entry ?_ "w" tbl)
    tbl)
  "The syntax table to use for fontifying Crystal mode buffers.
See `font-lock-syntax-table'.")

(defconst crystal-font-lock-keyword-beg-re "\\(?:^\\|[^.@$]\\|\\.\\.\\)")

(defconst crystal-font-lock-keywords
  `(;; Functions.
    ("^\\s *def\\s +\\(?:[^( \t\n.{}]*\\.\\)?\\([^( \t\n{}]+\\)"
     1 font-lock-function-name-face)
    ;; Keywords.
    (,(concat
       crystal-font-lock-keyword-beg-re
       (regexp-opt
        '("alias"
	  "and"
          "begin"
          "break"
          "case"
          "class"
          "def"
          "defined?"
          "do"
          "elsif"
          "else"
          "fail"
          "ensure"
          "enum"
          "for"
          "end"
          "if"
          "in"
          "lib"
          "macro"
          "module"
          "next"
          "not"
          "of"
          "or"
          "redo"
          "rescue"
          "retry"
          "return"
          "then"
          "struct"
          "super"
          "unless"
          "undef"
          "until"
          "when"
          "while"
          "yield"
          "lib"
          "struct"
          "enum"
          "fun"
          "type")
        'symbols))
     (1 font-lock-keyword-face))
    ;; Core methods that have required arguments.
    (,(concat
       crystal-font-lock-keyword-beg-re
       (regexp-opt
        '( ;; built-in methods on Kernel
          "at_exit"
          "autoload"
          "autoload?"
          "catch"
          "eval"
          "exec"
          "fork"
          "format"
          "load"
          "loop"
          "open"
          "p"
          "pp"
          "print"
          "printf"
          "putc"
          "puts"
          "require"
          "spawn"
          "sprintf"
          "syscall"
          "system"
          "trap"
          "warn"
          ;; keyword-like private methods on Module
          "alias_method"
          "attr"
          "property"
          "getter"
          "setter"
          "define_method"
          "extend"
          "include"
          "module_function"
          "prepend"
          "private_class_method"
          "private_constant"
          "public_class_method"
          "public_constant"
          "refine"
          "using")
        'symbols))
     (1 (unless (looking-at " *\\(?:[]|,.)}=]\\|$\\)")
          font-lock-builtin-face)))
    ;; Kernel methods that have no required arguments.
    (,(concat
       crystal-font-lock-keyword-beg-re
       (regexp-opt
        '("__callee__"
          "__dir__"
          "__method__"
          "abort"
          "at_exit"
          "binding"
          "block_given?"
          "caller"
          "exit"
          "exit!"
          "fail"
          "abstract"
          "private"
          "protected"
          "public"
          "raise"
          "rand"
          "readline"
          "readlines"
          "sleep"
          "srand"
          "throw")
        'symbols))
     (1 font-lock-builtin-face))
    ;; Here-doc beginnings.
    (,crystal-here-doc-beg-re
     (0 (unless (crystal-singleton-class-p (match-beginning 0))
          'font-lock-string-face)))
    ;; Perl-ish keywords.
    "\\_<\\(?:BEGIN\\|END\\)\\_>\\|^__END__$"
    ;; Variables.
    (,(concat crystal-font-lock-keyword-beg-re
              "\\_<\\(nil\\|self\\|true\\|false\\)\\_>")
     1 font-lock-variable-name-face)
    ;; Keywords that evaluate to certain values.
    ("\\_<__\\(?:LINE\\|ENCODING\\|FILE\\)__\\_>"
     (0 font-lock-builtin-face))
    ;; Symbols.
    ("\\(^\\|[^:]\\)\\(:\\([-+~]@?\\|[/%&|^`]\\|\\*\\*?\\|<\\(<\\|=>?\\)?\\|>[>=]?\\|===?\\|=~\\|![~=]?\\|\\[\\]=?\\|@?\\(\\w\\|_\\)+\\([!?=]\\|\\b_*\\)\\|#{[^}\n\\\\]*\\(\\\\.[^}\n\\\\]*\\)*}\\)\\)"
     2 font-lock-constant-face)
    ;; Special globals.
    (,(concat "\\$\\(?:[:\"!@;,/\\._><\\$?~=*&`'+0-9]\\|-[0adFiIlpvw]\\|"
              (regexp-opt '("LOAD_PATH" "LOADED_FEATURES" "PROGRAM_NAME"
                            "ERROR_INFO" "ERROR_POSITION"
                            "FS" "FIELD_SEPARATOR"
                            "OFS" "OUTPUT_FIELD_SEPARATOR"
                            "RS" "INPUT_RECORD_SEPARATOR"
                            "ORS" "OUTPUT_RECORD_SEPARATOR"
                            "NR" "INPUT_LINE_NUMBER"
                            "LAST_READ_LINE" "DEFAULT_OUTPUT" "DEFAULT_INPUT"
                            "PID" "PROCESS_ID" "CHILD_STATUS"
                            "LAST_MATCH_INFO" "IGNORECASE"
                            "ARGV" "MATCH" "PREMATCH" "POSTMATCH"
                            "LAST_PAREN_MATCH" "stdin" "stdout" "stderr"
                            "DEBUG" "FILENAME" "VERBOSE" "SAFE" "CLASSPATH"))
              "\\_>\\)")
     0 font-lock-builtin-face)
    ("\\(\\$\\|@\\|@@\\)\\(\\w\\|_\\)+"
     0 font-lock-variable-name-face)
    ;; Attributes
    (, crystal-attr-re
     (1 font-lock-preprocessor-face)
     (3 font-lock-preprocessor-face))
    ;; Constants.
    ("\\(?:\\_<\\|::\\|\\s+:\\s+\\)\\([A-Z]+\\(\\w\\|_\\)*\\)"
     1 (unless (eq ?\( (char-after)) font-lock-type-face))
    ("\\(^\\s *\\|[\[\{\(,]\\s *\\|\\sw\\s +\\)\\(\\(\\sw\\|_\\)+\\):[^:]"
     (2 font-lock-constant-face))
    ;; Conversion methods on Kernel.
    (,(concat crystal-font-lock-keyword-beg-re
              (regexp-opt '("Array" "Complex" "Float" "Hash"
                            "Integer" "Rational" "String" "Tuple" "NamedTuple") 'symbols))
     (1 font-lock-builtin-face))
    ;; Expression expansion.
    (crystal-match-expression-expansion
     2 font-lock-variable-name-face t)
    ;; Negation char.
    ("\\(?:^\\|[^[:alnum:]_]\\)\\(!+\\)[^=~]"
     1 font-lock-negation-char-face)
    ;; Character literals.
    ;; FIXME: Support longer escape sequences.
    ("\\_<\\?\\\\?\\S " 0 font-lock-string-face)
    ;; macro delimiters
    ("\\({%\\|{{\\|}}\\|%}\\)" 1 font-lock-preprocessor-face)
    ;; Regexp options.
    ("\\(?:\\s|\\|/\\)\\([imxo]+\\)"
     1 (when (save-excursion
               (let ((state (syntax-ppss (match-beginning 0))))
                 (and (nth 3 state)
                      (or (eq (char-after) ?/)
                          (progn
                            (goto-char (nth 8 state))
                            (looking-at "%r"))))))
         font-lock-preprocessor-face))
    )
  "Additional expressions to highlight in Crystal mode.")

(defun crystal-match-expression-expansion (limit)
  (let* ((prop 'crystal-expansion-match-data)
         (pos (next-single-char-property-change (point) prop nil limit))
         value)
    (when (and pos (> pos (point)))
      (goto-char pos)
      (or (and (setq value (get-text-property pos prop))
               (progn (set-match-data value) t))
          (crystal-match-expression-expansion limit)))))

;;;; Crystal tooling functions
(defun crystal-exec (args output-buffer-name)
  "Run crystal with the supplied args and put the result in output-buffer-name"
  (apply 'call-process
         (append (list crystal-executable nil output-buffer-name t)
                 args)))

(defun crystal-format ()
  "Format the contents of the current buffer without persisting the result."
  (interactive)
  (let ((oldbuf (current-buffer))
        (name (make-temp-file "crystal-format")))
    (with-temp-file name (insert-buffer-substring oldbuf))
    (crystal-exec (list "tool" "format" name) "*messages*")
    (insert-file-contents name nil nil nil t)))

;;;###autoload
(define-derived-mode crystal-mode prog-mode "Crystal"
  "Major mode for editing Crystal code.

\\{crystal-mode-map}"
  (crystal-mode-variables)

  (setq-local imenu-create-index-function 'crystal-imenu-create-index)
  (setq-local add-log-current-defun-function 'crystal-add-log-current-method)
  (setq-local beginning-of-defun-function 'crystal-beginning-of-defun)
  (setq-local end-of-defun-function 'crystal-end-of-defun)

  (add-hook 'after-save-hook 'crystal-mode-set-encoding nil 'local)
  (add-hook 'electric-indent-functions 'crystal--electric-indent-p nil 'local)

  (setq-local font-lock-defaults '((crystal-font-lock-keywords) nil nil))
  (setq-local font-lock-keywords crystal-font-lock-keywords)
  (setq-local font-lock-syntax-table crystal-font-lock-syntax-table)

  (setq-local syntax-propertize-function #'crystal-syntax-propertize-function))

;;; Invoke crystal-mode when appropriate

;;;###autoload
(add-to-list 'auto-mode-alist
             (cons (purecopy (concat "\\(?:\\."
                                     "cr"
                                     "\\)\\'")) 'crystal-mode))

;;;###autoload
(dolist (name (list "crystal"))
  (add-to-list 'interpreter-mode-alist (cons (purecopy name) 'crystal-mode)))

(provide 'crystal-mode)

;;; crystal-mode.el ends here
