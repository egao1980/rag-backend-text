(in-package #:rag-backend-text)

;;; Recursive character splitter (LangChain-shaped): try separators, then pack
;;; units to SIZE with OVERLAP. Size is in CL characters, not bytes.

(defclass recursive-character-chunker (rag-protocol:rag-chunker)
  ((size :initarg :size :accessor chunker-size :initform 1000)
   (overlap :initarg :overlap :accessor chunker-overlap :initform 200)
   (separators :initarg :separators :accessor chunker-separators
               :initform '("\n\n" "\n" " " ""))))

(defun make-recursive-character-chunker (&key (size 1000) (overlap 200)
                                           (separators '("\n\n" "\n" " " "")))
  (when (and overlap size (>= overlap size))
    (error 'rag-protocol:rag-error
           :message (format nil "overlap ~d must be < size ~d" overlap size)))
  (make-instance 'recursive-character-chunker
                 :size size :overlap overlap :separators separators))

(defun use-recursive-character-chunker (&rest args &key &allow-other-keys)
  (setf rag-protocol:*rag-chunker*
        (apply #'make-recursive-character-chunker args)))

(defun %split-by (text separator)
  (if (string= separator "")
      (loop for i from 0 below (length text)
            collect (string (char text i)))
      (let ((parts '())
            (start 0)
            (sep-len (length separator)))
        (loop for pos = (search separator text :start2 start)
              while pos
              do (push (subseq text start (+ pos sep-len)) parts)
                 (setf start (+ pos sep-len)))
        (push (subseq text start) parts)
        (nreverse (remove-if (lambda (p) (zerop (length p))) parts)))))

(defun %best-separator (text separators)
  (or (find-if (lambda (sep)
                 (and (plusp (length sep)) (search sep text)))
               separators)
      (car (last separators))
      ""))

(defun %rest-separators (separator separators)
  (let ((tail (member separator separators :test #'string=)))
    (if (and tail (cdr tail))
        (cdr tail)
        '(""))))

(defun %hard-cut (text size overlap)
  (let ((n (length text))
        (step (max 1 (- size (or overlap 0))))
        (out '()))
    (loop for start from 0 below n by step
          for end = (min n (+ start size))
          do (push (subseq text start end) out)
          until (>= end n))
    (nreverse out)))

(defun %split-text (text separators size overlap)
  (cond
    ((zerop (length text)) '())
    ((<= (length text) size) (list text))
    (t
     (let* ((sep (%best-separator text separators))
            (rest (%rest-separators sep separators)))
       (if (string= sep "")
           (%hard-cut text size overlap)
           (mapcan (lambda (part)
                     (if (> (length part) size)
                         (%split-text part rest size overlap)
                         (list part)))
                   (%split-by text sep)))))))

(defun %pack (units size overlap)
  (let ((n (length units))
        (chunks '())
        (i 0))
    (loop while (< i n)
          do (let ((buf '())
                   (len 0)
                   (j i))
               (loop while (and (< j n)
                                (let ((ulen (length (nth j units))))
                                  (or (null buf)
                                      (<= (+ len ulen) size))))
                     do (let ((u (nth j units)))
                          (push u buf)
                          (incf len (length u))
                          (incf j)))
               (when buf
                 (push (apply #'concatenate 'string (nreverse buf)) chunks))
               (cond
                 ((= j i)
                  (incf i))
                 ((zerop (or overlap 0))
                  (setf i j))
                 (t
                  (let ((olen 0)
                        (keep 0))
                    (loop for k from (1- j) downto i
                          while (and (< olen overlap)
                                     (< keep (- j i)))
                          do (incf keep)
                             (incf olen (length (nth k units))))
                    (setf i (max (+ i 1) (- j keep))))))))
    (nreverse (remove-if (lambda (s) (zerop (length s))) chunks))))

(defun %split (text size overlap separators)
  (let ((units (%split-text text separators size overlap)))
    (if (and units (every (lambda (u) (<= (length u) size)) units))
        (%pack units size overlap)
        (mapcan (lambda (u)
                  (if (> (length u) size)
                      (%hard-cut u size overlap)
                      (list u)))
                units))))

(defmethod rag-protocol:chunk ((chunker recursive-character-chunker)
                               (document rag-protocol:rag-document)
                               &key size overlap)
  (let* ((size (or size (chunker-size chunker)))
         (overlap (or overlap (chunker-overlap chunker)))
         (texts (%split (rag-protocol:rag-document-text document)
                        size overlap (chunker-separators chunker)))
         (doc-id (rag-protocol:rag-document-id document))
         (base (copy-list (rag-protocol:rag-document-metadata document))))
    (loop for text in texts
          for i from 0
          collect (rag-protocol:make-rag-chunk
                   :id (format nil "~a:~d" doc-id i)
                   :document-id doc-id
                   :text text
                   :metadata (list* :chunk-index i base)))))
