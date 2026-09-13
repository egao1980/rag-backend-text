(in-package #:rag-backend-text/tests)

(defclass mock-object-store (object-store-protocol:object-store)
  ((puts :initform nil :accessor mock-store-puts)))

(defmethod object-store-protocol:put-object ((store mock-object-store) key data
                                             &key content-type metadata
                                               if-match if-none-match)
  (declare (ignore content-type metadata if-match if-none-match))
  (let ((octets (object-store-protocol:coerce-object-octets data)))
    (push (cons key octets) (mock-store-puts store))
    (object-store-protocol:make-object-stat :key key :size (length octets))))

(defun %table ()
  (doc-extract-protocol:make-table-block
   :rows 2 :cols 2
   :cells
   (list (doc-extract-protocol:make-table-cell
          :row 0 :col 0 :header-p t
          :content (list (doc-extract-protocol:make-text-block :text "H1")))
         (doc-extract-protocol:make-table-cell
          :row 0 :col 1 :header-p t
          :content (list (doc-extract-protocol:make-text-block :text "H2")))
         (doc-extract-protocol:make-table-cell
          :row 1 :col 0
          :content (list (doc-extract-protocol:make-text-block :text "a")))
         (doc-extract-protocol:make-table-cell
          :row 1 :col 1
          :content (list (doc-extract-protocol:make-text-block :text "b"))))))

(defun %sample-doc (&key image-octets)
  (let* ((para (doc-extract-protocol:make-text-block :text "Hello body."))
         (table (%table))
         (caption (doc-extract-protocol:make-text-block :text "Table of values"))
         (img (doc-extract-protocol:make-image-block
               :alt "a figure"
               :octets image-octets))
         (foot (doc-extract-protocol:make-text-block
                :text "Page 1 footer"
                :layer :furniture
                :attrs '(:role :page-footer)))
         (sec (doc-extract-protocol:make-section-block
               :title "Intro"
               :level 1
               :children (list para table caption img foot)))
         (doc (doc-extract-protocol:ensure-ids
               (doc-extract-protocol:make-extracted-document
                :metadata (doc-extract-protocol:make-document-metadata
                           :title "Sample" :filename "sample.pdf")
                :blocks (list sec)))))
    (let ((tid (doc-extract-protocol:block-id table))
          (cid (doc-extract-protocol:block-id caption)))
      (when (and tid cid)
        (setf (doc-extract-protocol:extracted-document-relations doc)
              (list (doc-extract-protocol:make-block-relation
                     :kind :caption-of :from-id cid :to-id tid)))))
    doc))

(defun %chunk-doc (doc &key store)
  (rag-backend-text:chunk-extracted-document
   (rag-backend-text:make-block-tree-chunker :store store)
   doc
   :document-id "sample"
   :store store))

(deftest use-block-tree-binds
  (let ((rag-protocol:*rag-chunker* nil))
    (rag-backend-text:use-block-tree-chunker)
    (ok (typep rag-protocol:*rag-chunker*
               'rag-backend-text:block-tree-chunker))))

(deftest block-id-present-and-resolves
  (let* ((doc (%sample-doc))
         (chunks (%chunk-doc doc)))
    (ok (plusp (length chunks)))
    (dolist (ch chunks)
      (let ((id (getf (rag-protocol:rag-chunk-metadata ch) :block-id)))
        (ok (and (stringp id) (plusp (length id))))
        (ok (doc-extract-protocol:find-block doc id))
        (ok (getf (rag-protocol:rag-chunk-metadata ch) :section-path))))))

(deftest furniture-excluded
  (let* ((doc (%sample-doc))
         (chunks (%chunk-doc doc))
         (texts (mapcar #'rag-protocol:rag-chunk-text chunks)))
    (ok (notany (lambda (s) (search "footer" s :test #'char-equal)) texts))
    (ok (notany (lambda (ch)
                  (let* ((id (getf (rag-protocol:rag-chunk-metadata ch) :block-id))
                         (b (and id (doc-extract-protocol:find-block doc id))))
                    (and b (eq (doc-extract-protocol:block-layer b) :furniture))))
                chunks))))

(deftest table-chunk-is-markdown
  (let* ((doc (%sample-doc))
         (chunks (%chunk-doc doc))
         (table (find :table chunks
                      :key (lambda (ch)
                             (getf (rag-protocol:rag-chunk-metadata ch) :kind)))))
    (ok table)
    (ok (search "|" (rag-protocol:rag-chunk-text table)))
    (ok (search "H1" (rag-protocol:rag-chunk-text table)))
    (ok (search "Table of values" (rag-protocol:rag-chunk-text table)))))

(deftest image-store-ref
  (let* ((octets (make-array 4 :element-type '(unsigned-byte 8)
                             :initial-contents '(1 2 3 4)))
         (doc (%sample-doc :image-octets octets))
         (store (make-instance 'mock-object-store))
         (chunks (%chunk-doc doc :store store))
         (img (find :image chunks
                    :key (lambda (ch)
                           (getf (rag-protocol:rag-chunk-metadata ch) :kind))))
         (meta (and img (rag-protocol:rag-chunk-metadata img)))
         (ref (getf meta :image-ref)))
    (ok img)
    (ok (stringp ref))
    (ok (plusp (length ref)))
    (ok (assoc ref (mock-store-puts store) :test #'equal))
    (ok (null (getf meta :image-octets)))))

(deftest image-octets-inline-without-store
  (let* ((octets (make-array 3 :element-type '(unsigned-byte 8)
                             :initial-contents '(9 8 7)))
         (doc (%sample-doc :image-octets octets))
         (chunks (%chunk-doc doc))
         (img (find :image chunks
                    :key (lambda (ch)
                           (getf (rag-protocol:rag-chunk-metadata ch) :kind))))
         (meta (and img (rag-protocol:rag-chunk-metadata img))))
    (ok img)
    (ok (equalp octets (getf meta :image-octets)))))

(deftest chunk-via-rag-document-metadata
  (let* ((doc (%sample-doc))
         (rag (rag-protocol:make-rag-document
               :id "via-meta"
               :text (doc-extract-protocol:document-text doc)
               :metadata (list :extracted-document doc)))
         (chunks (rag-protocol:chunk
                  (rag-backend-text:make-block-tree-chunker)
                  rag)))
    (ok (plusp (length chunks)))
    (ok (every (lambda (ch)
                 (doc-extract-protocol:find-block
                  doc (getf (rag-protocol:rag-chunk-metadata ch) :block-id)))
               chunks))))

(deftest missing-extracted-document-signals
  (ok (signals (rag-protocol:chunk
                (rag-backend-text:make-block-tree-chunker)
                (rag-protocol:make-rag-document :id "x" :text "plain"))
               'rag-protocol:rag-error)))
