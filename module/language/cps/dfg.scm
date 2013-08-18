;;; Continuation-passing style (CPS) intermediate language (IL)

;; Copyright (C) 2013 Free Software Foundation, Inc.

;;;; This library is free software; you can redistribute it and/or
;;;; modify it under the terms of the GNU Lesser General Public
;;;; License as published by the Free Software Foundation; either
;;;; version 3 of the License, or (at your option) any later version.
;;;;
;;;; This library is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;;; Lesser General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU Lesser General Public
;;;; License along with this library; if not, write to the Free Software
;;;; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA

;;; Commentary:
;;;
;;;
;;; Code:

(define-module (language cps dfg)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (srfi srfi-9)
  #:use-module (srfi srfi-26)
  #:use-module (language cps)
  #:export (build-cont-table
            build-local-cont-table
            lookup-cont

            compute-local-dfg
            compute-dfg
            dfg-cont-table
            lookup-def
            lookup-uses
            find-call
            call-expression
            find-expression
            find-defining-expression
            find-constant-value
            variable-used-in?
            constant-needs-allocation?
            dead-after-def?
            dead-after-use?
            branch?
            find-other-branches
            dead-after-branch?
            lookup-bound-syms))

(define (build-cont-table fun)
  (fold-conts (lambda (k src cont table)
                (hashq-set! table k cont)
                table)
              (make-hash-table)
              fun))

(define (build-local-cont-table cont)
  (fold-local-conts (lambda (k src cont table)
                      (hashq-set! table k cont)
                      table)
                    (make-hash-table)
                    cont))

(define (lookup-cont sym conts)
  (let ((res (hashq-ref conts sym)))
    (unless res
      (error "Unknown continuation!" sym (hash-fold acons '() conts)))
    res))

;; Data-flow graph for CPS: both for values and continuations.
(define-record-type $dfg
  (make-dfg conts use-maps uplinks)
  dfg?
  ;; hash table of sym -> $kargs, $kif, etc
  (conts dfg-cont-table)
  ;; hash table of sym -> $use-map
  (use-maps dfg-use-maps)
  ;; hash table of sym -> $parent-link
  (uplinks dfg-uplinks))

(define-record-type $use-map
  (make-use-map sym def uses)
  use-map?
  (sym use-map-sym)
  (def use-map-def)
  (uses use-map-uses set-use-map-uses!))

(define-record-type $uplink
  (make-uplink parent level)
  uplink?
  (parent uplink-parent)
  (level uplink-level))

(define (visit-entry self entry conts use-maps uplinks global?)
  (define (add-def! sym def-k)
    (unless def-k
      (error "Term outside labelled continuation?"))
    (hashq-set! use-maps sym (make-use-map sym def-k '())))

  (define (add-use! sym use-k)
    (match (hashq-ref use-maps sym)
      (#f (error "Symbol out of scope?" sym))
      ((and use-map ($ $use-map sym def uses))
       (set-use-map-uses! use-map (cons use-k uses)))))

  (define (link-parent! k parent)
    (match (hashq-ref uplinks parent)
      (($ $uplink _ level)
       (hashq-set! uplinks k (make-uplink parent (1+ level))))))

  (define (visit exp exp-k)
    (define (def! sym)
      (add-def! sym exp-k))
    (define (use! sym)
      (add-use! sym exp-k))
    (define (recur exp)
      (visit exp exp-k))
    (match exp
      (($ $letk conts body)
       (for-each recur conts)
       (recur body))

      (($ $cont k src cont)
       (def! k)
       (hashq-set! conts k cont)
       (link-parent! k exp-k)
       (visit cont k))

      (($ $kargs names syms body)
       (for-each def! syms)
       (recur body))

      (($ $kif kt kf)
       (use! kt)
       (use! kf))

      (($ $ktrunc arity k)
       (use! k))

      (($ $ktail)
       #f)

      (($ $fun meta self free entries)
       (unless global?
         (error "pass a $cont when building a local DFG"))
       (for-each (cut visit-entry self <> conts use-maps uplinks global?)
                 entries))

      (($ $letrec names syms funs body)
       (unless global?
         (error "$letrec should not be present when building a local DFG"))
       (for-each def! syms)
       (for-each (cut visit <> #f) funs)
       (visit body exp-k))

      (($ $continue k exp)
       (use! k)
       (match exp
         (($ $var sym)
          (use! sym))

         (($ $call proc args)
          (use! proc)
          (for-each use! args))

         (($ $primcall name args)
          (for-each use! args))

         (($ $values args)
          (for-each use! args))

         (($ $prompt escape? tag handler)
          (use! tag)
          (use! handler))

         (($ $fun)
          (when global? (visit exp #f)))

         (_ #f)))))

  (match entry
    ;; Treat the entry continuation as its own parent.
    (($ $cont k src ($ $kentry arity tail body))
     (add-def! k k)
     ;; FIXME: Define self in one place, not in each entry
     (add-def! self k)
     (hashq-set! uplinks k (make-uplink #f 0))
     (visit tail k)
     (visit body k))))

(define* (compute-local-dfg self exp)
  (let* ((conts (make-hash-table))
         (use-maps (make-hash-table))
         (uplinks (make-hash-table)))
    (visit-entry self exp conts use-maps uplinks #f)
    (make-dfg conts use-maps uplinks)))

(define* (compute-dfg fun)
  (let* ((conts (make-hash-table))
         (use-maps (make-hash-table))
         (uplinks (make-hash-table)))
    (match fun
      (($ $fun meta self free entries)
       (for-each (cut visit-entry self <> conts use-maps uplinks #t)
                 entries)))
    (make-dfg conts use-maps uplinks)))

(define (lookup-uplink k uplinks)
  (let ((res (hashq-ref uplinks k)))
    (unless res
      (error "Unknown continuation!" k (hash-fold acons '() uplinks)))
    res))

(define (lookup-use-map sym use-maps)
  (let ((res (hashq-ref use-maps sym)))
    (unless res
      (error "Unknown lexical!" sym (hash-fold acons '() use-maps)))
    res))

(define (lookup-def sym dfg)
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (match (lookup-use-map sym use-maps)
       (($ $use-map sym def uses)
        def)))))

(define (lookup-uses sym dfg)
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (match (lookup-use-map sym use-maps)
       (($ $use-map sym def uses)
        uses)))))

(define (find-defining-term sym dfg)
  (match (lookup-uses (lookup-def sym dfg) dfg)
    ((def-exp-k)
     (lookup-cont def-exp-k (dfg-cont-table dfg)))
    (else #f)))

(define (find-call term)
  (match term
    (($ $kargs names syms body) (find-call body))
    (($ $letk conts body) (find-call body))
    (($ $letrec names syms funs body) (find-call body))
    (($ $continue) term)))

(define (call-expression call)
  (match call
    (($ $continue k exp) exp)))

(define (find-expression term)
  (call-expression (find-call term)))

(define (find-defining-expression sym dfg)
  (match (find-defining-term sym dfg)
    (#f #f)
    (($ $ktrunc) #f)
    (term (find-expression term))))

(define (find-constant-value sym dfg)
  (match (find-defining-expression sym dfg)
    (($ $const val)
     (values #t val))
    (($ $continue k ($ $void))
     (values #t *unspecified*))
    (else
     (values #f #f))))

(define (constant-needs-allocation? sym val dfg)
  (define (find-exp term)
    (match term
      (($ $kargs names syms body) (find-exp body))
      (($ $letk conts body) (find-exp body))
      (else term)))
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (match (lookup-use-map sym use-maps)
       (($ $use-map _ def uses)
        (or-map
         (lambda (use)
           (match (find-expression (lookup-cont use conts))
             (($ $call) #f)
             (($ $values) #f)
             (($ $primcall 'free-ref (closure slot))
              (not (eq? sym slot)))
             (($ $primcall 'free-set! (closure slot value))
              (not (eq? sym slot)))
             (($ $primcall 'cache-current-module! (mod . _))
              (eq? sym mod))
             (($ $primcall 'cached-toplevel-box _)
              #f)
             (($ $primcall 'cached-module-box _)
              #f)
             (($ $primcall 'resolve (name bound?))
              (eq? sym name))
             (_ #t)))
         uses))))))

(define (continuation-scope-contains? parent-k k uplinks)
  (match (lookup-uplink parent-k uplinks)
    (($ $uplink _ parent-level)
     (let lp ((k k))
       (or (eq? parent-k k)
           (match (lookup-uplink k uplinks)
             (($ $uplink parent level)
              (and (< parent-level level)
                   (lp parent)))))))))

(define (variable-used-in? var parent-k dfg)
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (or-map (lambda (use)
               (continuation-scope-contains? parent-k use uplinks))
             (match (lookup-use-map var use-maps)
               (($ $use-map sym def uses)
                uses))))))

;; Does k1 dominate k2?
;;
;; Note that this is a conservative predicate: a false return value does
;; not indicate that k1 _doesn't_ dominate k2.  The reason for this is
;; that we are using the scope tree as an approximation of the dominator
;; relationship.  See
;; http://mlton.org/pipermail/mlton/2003-January/023054.html for a
;; deeper discussion.
(define (conservatively-dominates? k1 k2 uplinks)
  (continuation-scope-contains? k1 k2 uplinks))

(define (dead-after-def? sym dfg)
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (match (lookup-use-map sym use-maps)
       (($ $use-map sym def uses)
        (null? uses))))))

(define (dead-after-use? sym use-k dfg)
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (match (lookup-use-map sym use-maps)
       (($ $use-map sym def uses)
        ;; If all other uses dominate this use, it is now dead.  There
        ;; are other ways for it to be dead, but this is an
        ;; approximation.  A better check would be if the successor
        ;; post-dominates all uses.
        (and-map (cut conservatively-dominates? <> use-k uplinks)
                 uses))))))

;; A continuation is a "branch" if all of its predecessors are $kif
;; continuations.
(define (branch? k dfg)
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (match (lookup-use-map k use-maps)
       (($ $use-map sym def uses)
        (and (not (null? uses))
             (and-map (lambda (k)
                        (match (lookup-cont k conts)
                          (($ $kif) #t)
                          (_ #f)))
                      uses)))))))

(define (find-other-branches k dfg)
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (match (lookup-use-map k use-maps)
       (($ $use-map sym def (uses ..1))
        (map (lambda (kif)
               (match (lookup-cont kif conts)
                 (($ $kif (? (cut eq? <> k)) kf)
                  kf)
                 (($ $kif kt (? (cut eq? <> k)))
                  kt)
                 (_ (error "Not all predecessors are branches"))))
             uses))))))

(define (dead-after-branch? sym branch other-branches dfg)
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (match (lookup-use-map sym use-maps)
       (($ $use-map sym def uses)
        (and-map
         (lambda (use-k)
           ;; A symbol is dead after a branch if at least one of the
           ;; other branches dominates a use of the symbol, and all
           ;; other uses of the symbol dominate the test.
           (if (or-map (cut conservatively-dominates? <> use-k uplinks)
                       other-branches)
               (not (conservatively-dominates? branch use-k uplinks))
               (conservatively-dominates? use-k branch uplinks)))
         uses))))))

(define (lookup-bound-syms k dfg)
  (match dfg
    (($ $dfg conts use-maps uplinks)
     (match (lookup-cont k conts)
       (($ $kargs names syms body)
        syms)))))
