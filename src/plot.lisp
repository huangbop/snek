
(in-package :plot)


(defun make-coverage-array (size)
  (make-array
    (list size size)
    :adjustable nil
    :initial-element 0
    :element-type 'integer))


(defstruct plot
  (verts nil :read-only nil)
  (edges nil :read-only nil)
  (lines nil :read-only nil)
  (coverage nil :read-only nil)
  (num-verts 0 :type integer :read-only nil)
  (num-edges 0 :type integer :read-only nil)
  (num-lines 0 :type integer :read-only nil)
  (discards 0 :type integer :read-only nil)
  (size nil :type integer :read-only nil))


(defun make (size)
  (make-plot
    :size size
    :verts (make-vec)
    :edges (make-vec)
    :lines (make-vec)
    :coverage (make-coverage-array size)))


(defun dot-stroke (plt line num)
  (with-struct (plot- size verts coverage) plt
    (destructuring-bind (u v)
      line
      (loop for xy in (math:nrep num (rnd:on-line u v)) do
        (inside* (size xy x y)
          (incf (aref coverage x y))
          (vector-push-extend xy verts))))))


(defun -ok-coverage (size coverage offset a b)
  (let ((itt (round (* 2.0d0 (math:len offset))))
        (cov-count 0)
        (cov (make-vec)))
    (loop for s in (math:linspace 0.0 1.0 itt) do
      (inside* (size (math:on-line s a b) x y)
        (incf cov-count (if (> (aref coverage x y) 0) 1 0))
        (vector-push-extend (list x y) cov)))

    (if (< cov-count (half itt))
      (progn
        ; todo: avoid coerce?
        (loop for (x y) in (coerce cov 'list) do
          (incf (aref coverage x y)))
        t)
      nil)))


(defun vflip (v)
  (destructuring-bind (a b)
    v
    (list b (- 0 a))))


(defun -coverage-path (size coverage path)
  (loop
    for a in path and b in (cdr path) do
      (let ((n (* 2 (round (math:dst a b)))))
        (loop for s in (math:linspace 0.0 1.0 n) do
          (inside* (size (math:on-line s a b) x y)
            (incf (aref coverage x y)))))))


(defun path (plt path &aux (n (length path)))
  (with-struct (plot- size verts lines num-verts coverage) plt
    ; todo: test if path is outside boundary
    (dolist (p path)
      (vector-push-extend p verts))
    (vector-push-extend
      (math:range num-verts (+ num-verts n)) lines)
    (incf (plot-num-verts plt) n)
    (incf (plot-num-lines plt))
    (-coverage-path size coverage path)))


(defun -stipple (plt xy offset)
  (with-struct (plot- size verts edges coverage) plt
    (let ((nv (plot-num-verts plt)))
      (let ((a (math:sub xy offset))
            (b (math:add xy offset)))

        (if (-ok-coverage size coverage offset a b)
          (progn
            (vector-push-extend a verts)
            (vector-push-extend b verts)
            (vector-push-extend (list nv (1+ nv)) edges)
            (incf (plot-num-verts plt) 2)
            (incf (plot-num-edges plt) 1)
            0)
          1)))))


(defun -get-offset (u v s perp)
  (let ((off (math:scale (math:nsub u v) s)))
    (if perp (vflip off) off)))


(defun stipple-stroke (plt line num s &key perp)
  (with-struct (plot- size) plt
    (destructuring-bind (u v)
      line
      (let ((offset (-get-offset u v s perp)))
        (loop for xy in (math:nrep num (rnd:on-line u v)) do
          (inside (size xy)
            (incf (plot-discards plt)
                  (-stipple plt xy offset))))))))


; this wrapper is probably inefficient.
(defun stipple-strokes (plt lines num s &key perp)
  (loop for line in lines do
    (stipple-stroke plt line num s :perp perp)))


(defun -png-tuple (v) (list v v v 255))


(defun -write-png (coverage size fn)
  (let ((png (make-instance
               'zpng::pixel-streamed-png
               :color-type :truecolor-alpha
               :width size
               :height size)))

        (with-open-file
          (stream fn
            :direction :output
            :if-exists :supersede
            :if-does-not-exist :create
            :element-type '(unsigned-byte 8))
          (zpng:start-png png stream)

          (square-loop (x y size)
            (zpng:write-pixel
              (if (> (aref coverage y x) 0)
                (-png-tuple 0)
                (-png-tuple 255))
              png))
          (zpng:finish-png png))))


(defun -write-2obj (verts edges lines fn)
  (with-open-file (stream fn :direction :output :if-exists :supersede)
    (format stream "o mesh~%")
    (dolist (ll (coerce verts 'list))
      (destructuring-bind (a b)
        ll
        (format stream "v ~f ~f~%" a b)))
    (if edges
      (dolist (ee (coerce edges 'list))
        (destructuring-bind (a b)
          (math:add ee '(1 1))
          (format stream "e ~d ~d~%" a b))))
    (if lines
      (dolist (ll (coerce lines 'list))
        (format stream "l")
        (dolist (l ll)
          (format stream " ~d" (1+ l)))
        (format stream "~%")))))


(defun save (plt fn)
  (let ((fn* (aif fn fn
                     (progn
                        (warn "missing file name, using: tmp.png")
                        "tmp"))))
    (let ((fnimg (append-postfix fn* ".png"))
          (fnobj (append-postfix fn* ".2obj")))
      (with-struct (plot- size verts edges lines coverage
                          num-verts num-edges num-lines discards) plt
        (-write-png coverage size fnimg)
        (-write-2obj verts edges lines fnobj)
        (format t "~%~%num verts: ~a ~%" num-verts)
        (format t "num edges: ~a ~%" num-edges)
        (format t "num lines ~a ~%" num-lines)
        (format t "num discards: ~a ~%" discards))
      (format t "~%files ~a" fnimg)
      (format t "~%      ~a~%~%" fnobj))))

