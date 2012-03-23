;; Eports: Ports that can be suspended when they would block.

;;;; Copyright (C) 2012 Free Software Foundation, Inc.
;;;; 
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
;;;; 

(define-module (ice-9 eports)
  #:use-module (srfi srfi-9)
  #:use-module (rnrs bytevectors)
  #:use-module (ice-9 nio)
  #:export (;; EPorts: ports that suspend when they would block.
            eport?
            eport-fd
            eport-file-port
            fdes->eport
            file-port->eport
            drain-output
            close-eport

            current-read-waiter
            current-write-waiter

            accept-eport

            get-u8
            lookahead-u8
            get-bytevector-some
            get-bytevector-n
            get-bytevector-n!
            get-bytevector-delimited
            get-u8
            put-u8
            put-bytevector))

(define-record-type <eport>
  (make-eport fd readbuf writebuf file-port)
  eport?
  (fd eport-fd set-eport-fd!)
  (readbuf eport-readbuf set-eport-readbuf!)
  (writebuf eport-writebuf set-eport-writebuf!)
  (file-port eport-file-port))

(define (default-read-waiter eport)
  (error "read would block" eport))
(define current-read-waiter
  (make-parameter default-read-waiter))
(define (wait-for-readable eport)
  ((current-read-waiter) eport))

(define (default-write-waiter eport)
  (error "write would block" eport))
(define current-write-waiter
  (make-parameter default-write-waiter))
(define (wait-for-writable eport)
  ((current-write-waiter) eport))

;; It's important to avoid calling into the kernel too many times.  For
;; that reason we buffer the input and output, using <buf> objects.  The
;; bytes in a read buffer are laid out like this:
;;
;;                   already read | not yet | invalid
;;                       data     |  read   |  data
;;     readbuf: #vu8(r r r r r r r|u u u u u|x x x x x)
;;                                ^cur      ^end
;;
;; Similarly for a write buffer:
;;
;;                   already written  | not yet | invalid
;;                       data         | written |  data
;;     writebuf: #vu8(w w w w w w w w |u u u u u|x x x x x)
;;                                    ^cur      ^end
;;
;; We use a <buf> object for both purposes.
;;
(define-record-type <buf>
  (make-buf bv cur end)
  buf?
  (bv buf-bv)
  (cur buf-cur set-buf-cur!)
  (end buf-end set-buf-end!))

(define (make-fresh-buf n)
  (make-buf (make-bytevector n 0) 0 0))

;; Mark N bytes as having been read or written.  This advances CUR by N,
;; except in the case that CUR would be equal to END, in which case both
;; are reset to 0.
;;
(define (flush-buffer buf n)
  (let ((new-cur (+ (buf-cur buf) n))
        (end (buf-end buf)))
    (cond
     ((< new-cur end)
      (set-buf-cur! buf new-cur))
     ((= new-cur end)
      (set-buf-cur! buf 0)
      (set-buf-end! buf 0))
     (else
      (error "flushing too many bytes" buf n)))))

;; Create an NIO port that wraps FD.  The strange default sizes assume
;; that the memory is allocated inline to the bytevector, and thus has a
;; 12- or 24-byte header, and so they will have a total size of 500 and
;; 1012 or 512 and 1024, respectively.  The collector might do better
;; with sizes like these.
;;
(define* (fdes->eport fd #:key readable? writable?
                      (read-buffer-size 488)
                      (write-buffer-size 1000)
                      file-port)
  (let ((eport
         (make-eport
          fd
          (and readable? (make-fresh-buf read-buffer-size))
          (and writable? (make-fresh-buf write-buffer-size))
          file-port)))
    (when file-port
      (setvbuf file-port _IONBF))
    (fcntl fd F_SETFL O_NONBLOCK)
    eport))

(define* (file-port->eport file-port)
  (fdes->eport (fileno file-port)
               #:readable? (input-port? file-port)
               #:writable? (output-port? file-port)
               #:file-port file-port))

(define* (close-eport eport #:key (drain-output? #t))
  (let ((fd (eport-fd eport)))
    (when fd
      (when drain-output?
        (drain-output eport))
      (set-eport-fd! eport #f)
      (set-eport-readbuf! eport #f)
      (set-eport-writebuf! eport #f)
      (cond
       ((eport-file-port eport) => close-port)
       (else (close-fdes fd))))))

;; Accept a new connection on EPORT, an eport that wraps a
;; listening socket.  Returns two values: an eport for the new
;; connection, and the sockaddr.
;;
(define (accept-eport eport)
  (let ((pair (nio-accept (eport-fd eport))))
    (if pair
        (values (fdes->eport (car pair) #:readable? #t #:writable? #t)
                (cdr pair))
        (begin
          (wait-for-readable eport)
          (accept-eport eport)))))

;; Ensure that there are readable bytes in the buffer, or that the
;; buffer is at EOF.  Returns the actual number of available bytes.
;;
(define (fill-input eport)
  (let* ((buf (eport-readbuf eport))
         (bv (buf-bv buf))
         (cur (buf-cur buf))
         (end (buf-end buf))
         (len (bytevector-length bv)))
    (if (zero? (- len end))
        (error "fill-input should only be called when the readbuf is empty"))
    (let ((rv (nio-read (eport-fd eport) bv end (- len end))))
      (if (< rv 0)
          (begin
            (wait-for-readable eport)
            (fill-input eport))
          (let ((new-end (+ end rv)))
            (set-buf-end! buf new-end)
            (- new-end cur))))))

;; Write all buffered output: those bytes between CUR and END.  Advances
;; CUR to be equal to END.
;;
(define (drain-output eport)
  (let* ((buf (eport-writebuf eport))
         (bv (buf-bv buf)))
    (let lp ()
      (let ((cur (buf-cur buf))
            (end (buf-end buf)))
        (when (< cur end)
          (let ((written (nio-write (eport-fd eport)
                                    bv cur (- end cur))))
            (flush-buffer buf written)
            (when (< written (- end cur))
              (wait-for-writable eport)
              (lp))))))))

;; Ensure that there is some space in the writebuf that can be filled.
;; Will write data or shuffle buffered data in order to ensure this
;; condition.
;;
(define (ensure-writable eport)
  (let ((buf (eport-writebuf eport)))
    (unless buf
      (error "not a writable port" eport))
    (let lp ()
      (let* ((cur (buf-cur buf))
             (end (buf-end buf))
             (bv (buf-bv buf))
             (size (bytevector-length bv)))
        (when (= end size)
          (if (> (* cur 2) size)
              ;; The buffer is less than half full; shuffle the data to
              ;; make space.
              (begin
                (bytevector-copy! bv cur bv 0 (- end cur))
                (set-buf-cur! buf 0)
                (set-buf-end! buf (- end cur)))
              ;; The buffer is more than half full; write some data and
              ;; try again.
              (let ((written (nio-write (eport-fd eport)
                                        bv cur (- end cur))))
                (flush-buffer buf written)
                (when (< written (- end cur))
                  (wait-for-writable eport)
                  (lp)))))))))

;; Peek at the next octet from EPORT, blocking if necessary.
;;
(define (lookahead-u8 eport)
  (let ((buf (eport-readbuf eport)))
    (unless buf
      (error "not a readable port" eport))
    (let ((cur (buf-cur buf)))
      (if (< cur (buf-end buf))
          (bytevector-u8-ref (buf-bv buf) cur)
          (if (zero? (fill-input eport))
              the-eof-object
              (lookahead-u8 eport))))))

;; Fetch the next octet from EPORT.
;;
(define (get-u8 eport)
  (let ((buf (eport-readbuf eport)))
    (unless buf
      (error "not a readable port" eport))
    (let ((cur (buf-cur buf)))
      (if (< cur (buf-end buf))
          (begin
            (set-buf-cur! buf (1+ cur))
            (bytevector-u8-ref (buf-bv buf) cur))
          (if (zero? (fill-input eport))
              the-eof-object
              (get-u8 eport))))))

;; Put a byte back into the buf of the port.  Note that you are only
;; guaranteed to be able to put back as many bytes as your last
;; fill-input was able to read.
;;
(define (putback-u8 eport u8)
  (let ((buf (eport-readbuf eport)))
    (unless buf
      (error "not a readable port" eport))
    (let ((cur (buf-cur buf)))
      (if (zero? cur)
          (error "no space to putback byte" eport)
          (begin
            (set-buf-cur! buf (1- cur))
            (bytevector-u8-set! (buf-bv buf) cur u8))))))

;; Put a sequence of bytes back into the buf of the port.  Note that you
;; are only guaranteed to be able to put back as many bytes as your last
;; fill-input was able to read.  In practice, this means you should only
;; use this on the result of get-bytevector-some.
;;
(define* (putback-bytevector eport bv #:optional (start 0)
                             (count (- (bytevector-length bv) start)))
  (let ((buf (eport-readbuf eport)))
    (unless buf
      (error "not a readable port" eport))
    (let ((cur (buf-cur buf)))
      (if (> cur count)
          (error "no space to putback bytes" eport count)
          (begin
            (set-buf-cur! buf (- cur count))
            (bytevector-copy! bv start (buf-bv buf) (- cur count) count))))))

;; Read some bytes from EPORT, and return them as a bytevector.  If
;; bytes are available to be read, they are returned directly.  If no
;; bytes are immediately available, attempt to fill the buffer, and try
;; again.  If no bytes are available at all, return the EOF object.
;;
(define (get-bytevector-some eport)
  (let ((buf (eport-readbuf eport)))
    (unless buf
      (error "not a readable port" eport))
    (let* ((cur (buf-cur buf))
           (len (- (buf-end buf) cur)))
      (if (zero? len)
          (if (zero? (fill-input eport))
              the-eof-object
              (get-bytevector-some eport))
          (let ((ret (make-bytevector len)))
            (bytevector-copy! (buf-bv buf) cur ret 0 len)
            (flush-buffer buf len)
            ret)))))

;; Read bytes from EPORT until the byte DELIMITER is seen.  Return
;; two values: a bytevector of the bytes read, not including the
;; delimiter, and the delimiter, or the EOF object if EOF was
;; encountered first.
;;
(define* (get-bytevector-delimited eport predicate)
  (define (collect-result prev prev-len bv)
    (if (null? prev-len)
        bv
        (let ((out (make-bytevector (+ prev-len (bytevector-length bv)))))
          (bytevector-copy! bv 0 out prev-len (bytevector-length bv))
          (let lp ((prev prev) (prev-len prev-len))
            (cond
             ((null? prev) out)
             (else
              (let ((len (bytevector-length (car prev))))
                (bytevector-copy! (car prev) 0 out (- prev-len len) len)
                (lp (cdr prev) (- prev-len len)))))))))
  (let ((buf (eport-readbuf eport)))
    (unless buf
      (error "not a readable port" eport))
    (let* ((bv (buf-bv buf))
           (size (bytevector-length bv)))
      (let lp ((prev '()) (prev-len 0))
        (when (= (buf-cur buf) (buf-end buf))
          (fill-input eport))
        (let ((cur (buf-cur buf))
              (end (buf-end buf)))
          (let search ((i cur))
            (if (< i end)
                (if (predicate (bytevector-u8-ref bv i))
                    (let ((ret (make-bytevector (- i cur))))
                      (bytevector-copy! bv cur ret 0 (- i cur))
                      ;; Plus one for the delimiter
                      (flush-buffer buf (1+ (- i cur)))
                      (values ret (bytevector-u8-ref bv i)))
                    (search (1+ i)))
                (let ((len (- end cur)))
                  (if (zero? len)
                      ;; EOF
                      (values (if (zero? prev-len)
                                  the-eof-object
                                  (collect-result prev prev-len #vu8()))
                              the-eof-object)
                      (let ((ret (make-bytevector len)))
                        (bytevector-copy! bv cur ret 0 len)
                        (flush-buffer buf len)
                        (lp (cons ret prev) (+ len prev-len))))))))))))

;; Read COUNT bytes into bytevector DST, starting at offset START.
;; Return the actual number of bytes read, which may be less if EOF was
;; found first.
;;
(define* (get-bytevector-n! eport dst start count)
  (let lp ((start start) (count count) (total 0))
    (let* ((buf (eport-readbuf eport))
           (bv (buf-bv buf))
           (size (bytevector-length bv))
           (cur (buf-cur buf))
           (len (- (buf-end buf) cur)))
      (unless buf
        (error "not a readable port" eport))
      (if (<= count len)
          (begin
            (bytevector-copy! bv cur dst start count)
            (flush-buffer buf count)
            (+ total count))
          (begin
            (bytevector-copy! bv cur dst start len)
            (flush-buffer buf len)
            (if (zero? (fill-input eport))
                (+ total len)
                (lp (+ start len) (- count len) (+ total len))))))))

;; Read COUNT bytes from EPORT, returning them in a fresh bytevector.
;; The bytevector will be smaller if EOF was found before COUNT bytes
;; could be read.
;;
(define (get-bytevector-n eport count)
  (let* ((bv (make-bytevector count))
         (filled (get-bytevector-n! eport bv 0 count)))
    (if (= filled count)
        bv
        (let ((ret (make-bytevector filled)))
          (bytevector-copy! bv 0 ret 0 filled)
          ret))))

;; Write an octet to EPORT.  Note that in the normal case, the byte
;; will be buffered; you will need to call DRAIN-OUTPUT for this octet
;; to be written.
;;
(define (put-u8 eport u8)
  (ensure-writable eport)
  (let* ((buf (eport-writebuf eport))
         (end (buf-end buf)))
    (bytevector-u8-set! (buf-bv buf) end u8)
    (set-buf-end! buf (1+ end))))

(define* (put-bytevector eport bv #:optional (start 0)
                         (count (- (bytevector-length bv) start)))
  (ensure-writable eport)
  (let* ((buf (eport-writebuf eport))
         (size (bytevector-length (buf-bv buf))))
    (let lp ((start start) (count count))
      (let ((end (buf-end buf)))
        (cond
         ;; If BV can fit into the buffer, buffer it directly.
         ((<= count (- size end))
          (bytevector-copy! bv start (buf-bv buf) end count)
          (set-buf-end! buf (+ end count)))
         ;; If BV could fit into a flushed buffer, force output and try again.
         ((<= count size)
          (drain-output eport)
          (lp start count))
         ;; Otherwise, BV is bigger than the buffer.  Flush the buffer,
         ;; and write from BV directly, without copying.
         (else
          (drain-output eport)
          (let ((written (nio-write (eport-fd eport)
                                    bv start count)))
            (when (< written count)
              (wait-for-writable eport)
              (lp (+ start written) (- count written))))))))))
