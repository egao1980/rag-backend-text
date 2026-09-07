(in-package #:rag-backend-text/tests)

(defun %texts (chunks)
  (mapcar #'rag-protocol:rag-chunk-text chunks))

(defun %chunk (text &key (size 10) (overlap 0) (id "d"))
  (rag-protocol:chunk (rag-backend-text:make-recursive-character-chunker
                       :size size :overlap overlap)
                      (rag-protocol:make-rag-document :id id :text text)))

(deftest use-chunker-binds
  (let ((rag-protocol:*rag-chunker* nil))
    (rag-backend-text:use-recursive-character-chunker :size 32 :overlap 4)
    (ok (typep rag-protocol:*rag-chunker*
               'rag-backend-text:recursive-character-chunker))))

(deftest short-text-one-chunk
  (let ((chunks (%chunk "hello" :size 10)))
    (ok (= 1 (length chunks)))
    (ok (equal "hello" (first (%texts chunks))))
    (ok (equal "d:0" (rag-protocol:rag-chunk-id (first chunks))))))

(deftest empty-text
  (ok (null (%chunk "" :size 10))))

(deftest paragraph-split
  (let* ((text (format nil "aaaa~%~%bbbb"))
         (chunks (%chunk text :size 6 :overlap 0)))
    (ok (= 2 (length chunks)))
    (ok (equal "aaaa" (string-right-trim '(#\Newline) (first (%texts chunks)))))
    (ok (search "bbbb" (second (%texts chunks))))))

(deftest overlap-keeps-tail
  (let* ((text "one two three four")
         (chunks (%chunk text :size 10 :overlap 4))
         (texts (%texts chunks)))
    (ok (>= (length texts) 2))
    (ok (every (lambda (c) (<= (length c) 10)) texts))
    (let ((a (first texts))
          (b (second texts)))
      (ok (search (subseq a (max 0 (- (length a) 3))) b)))))

(deftest hard-cut-long-word
  (let* ((text "abcdefghijKLMN")
         (chunks (%chunk text :size 4 :overlap 0
                         :id "w"))
         (texts (%texts chunks)))
    (ok (every (lambda (c) (<= (length c) 4)) texts))
    (ok (equal "abcdefghijKLMN" (apply #'concatenate 'string texts)))))

(deftest overlap-invalid
  (ok (signals (rag-backend-text:make-recursive-character-chunker
                :size 8 :overlap 8)
               'rag-protocol:rag-error)))

(deftest string-document
  (let ((chunks (rag-protocol:chunk
                 (rag-backend-text:make-recursive-character-chunker :size 8 :overlap 0)
                 "abcdefghijkl")))
    (ok (>= (length chunks) 2))
    (ok (every #'rag-protocol:rag-chunk-p chunks))))

(deftest metadata-index
  (let ((chunks (%chunk "abcdefghij" :size 4 :overlap 0)))
    (ok (eql 0 (getf (rag-protocol:rag-chunk-metadata (first chunks)) :chunk-index)))
    (ok (eql 1 (getf (rag-protocol:rag-chunk-metadata (second chunks)) :chunk-index)))))
