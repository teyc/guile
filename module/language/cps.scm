(define-module (language cps)
  #:use-module (system base syntax) ;; for define-type
  #:export (<cps> cps?
            <letval> letval? make-letval letval-names letval-vals letval-body
            <letrec> letrec? make-letrec letrec-funcs letrec-body
            <letcont> letcont? make-letcont letcont-names
                      letcont-conts letcont-body
            <lambda> lambda? make-lambda lambda-names lambda-body
            <call> call? make-call call-proc call-cont call-args))

;; The CPS representation used in this file is based on the paper
;; "Compiling with Continuations, Continued", by Andrew Kennedy.
;; Although it's called CPS, it's not really what you (or at least I)
;; would think of as "traditional" CPS, because all the functions are
;; declared via 'let...' forms. <letcont> distinguishes functions which
;; a) will never need a closure allocated and b) do not take their
;; continuations as arguments. Every new function produced by the
;; Scheme->CPS transformation has this property.

;; This representation has some useful properties:

;;  1) first, it's a runnable Scheme program (or close enough to
;;  Scheme). The CPS transformation applies to every Scheme program and
;;  preserves semantics.

;;  2) the let-based CPS is a representation of the dominator tree of
;;  the control flow graph of this program. in every <let___> block, the
;;  code in the body must be executed before the funcs or conts, and
;;  once control exits the body, it never goes back. basically, the let
;;  forms represent some subset of the control flow graph in two parts,
;;  and control only flows one direction between the parts.

;;  3) every lexical variable gets a unique name, and if it is set!, the
;;  new value gets a new name! therefore the variable names track
;;  uniqueness in the eq? sense. also, since every variable gets a
;;  unique name, we don't have to bother with environment structures
;;  just to store properties - we just use the variable names as keys to
;;  a hash table and know that they won't collide.

(define-type <cps>
  ;; <letval> actually handles multiple constant values, because why
  ;; not?
  (<letval> names vals body)
  ;; Kennedy's paper calls this 'letfun', but 'letrec' is more standard
  ;; in Scheme
  (<letrec> names funcs body)
  ;; the important thing about continuations (as opposed to functions)
  ;; is that they can always be compiled as jumps. this is information
  ;; that was in the program itself, but would be lost if we compiled
  ;; everything to lambdas without distinguishing them in some
  ;; way. also, continuations can never be referenced by variables, so
  ;; we don't need to worry about packaging them up.
  (<letcont> names conts body)
  ;; the 'lambda' form appears in the 'funcs' list of a letrec form, the
  ;; 'conts' list of a letcont form, and as the outermost form of a
  ;; compilation unit (when we're compiling a procedure at a time) to
  ;; distinguish procedure arguments from top-level variables.
  (<lambda> names body)
  ;; the 'call' form literally represents a call. the procedure will be
  ;; a variable bound by either a lambda form, a letval, a letrec, or a
  ;; letcont, or the special value 'return (which means to return from
  ;; the enclosing lambda). cont is the continuation that we pass to the
  ;; procedure. it's separate from the args because it can point to a
  ;; letcont continuation and they cannot, so it is different for
  ;; purposes of register allocation (and, of course, code
  ;; generation). the cont slot will be #f if proc is a letcont
  ;; continuation or 'return.
  (<call> proc cont args)
  ;; right now we are missing the 'let' from Kennedy's paper. That is
  ;; used to compose record constructors and field accessors, but we are
  ;; not attempting to do that yet.
  )
