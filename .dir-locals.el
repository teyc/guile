;; Per-directory local variables for GNU Emacs 23 and later.

((nil             . ((fill-column . 72)
                     (tab-width   .  8)))
 (c-mode          . ((c-file-style . "gnu")))
 (scheme-mode
  . ((indent-tabs-mode . nil)
     (eval . (put 'pass-if             'scheme-indent-function 1))
     (eval . (put 'pass-if-exception   'scheme-indent-function 2))
     (eval . (put 'pass-if-equal       'scheme-indent-function 2))
     (eval . (put 'with-test-prefix    'scheme-indent-function 1))
     (eval . (put 'with-code-coverage  'scheme-indent-function 1))
     (eval . (put 'with-statprof       'scheme-indent-function 1))
     (eval . (put 'let-gensyms         'scheme-indent-function 1))
     (eval . (put 'build-cps-term      'scheme-indent-function 0))
     (eval . (put 'build-cps-call      'scheme-indent-function 0))
     (eval . (put 'build-cps-cont      'scheme-indent-function 0))
     (eval . (put 'rewrite-cps-term    'scheme-indent-function 1))
     (eval . (put 'rewrite-cps-cont    'scheme-indent-function 1))
     (eval . (put 'rewrite-cps-call    'scheme-indent-function 1))
     (eval . (put '$letk               'scheme-indent-function 1))
     (eval . (put '$letk*              'scheme-indent-function 1))
     (eval . (put '$letconst           'scheme-indent-function 1))
     (eval . (put '$continue           'scheme-indent-function 1))
     (eval . (put '$kargs              'scheme-indent-function 2))
     (eval . (put '$kentry             'scheme-indent-function 1))))
 (emacs-lisp-mode . ((indent-tabs-mode . nil)))
 (texinfo-mode    . ((indent-tabs-mode . nil)
                     (fill-column . 72))))
