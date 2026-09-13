(in-package #:rag-backend-text)

;;; Block-tree splitter (C3d2): walk :body blocks of an EXTRACTED-DOCUMENT.
;;; Table chunks are render-table markdown (+ caption). Furniture is skipped.
;;; Every chunk is stamped with :block-id + :section-path so citations resolve
;;; via doc-extract-protocol:FIND-BLOCK. Image octets are PUT on an optional
;;; object-store-protocol store (keyed by content hash); otherwise left inline.

(defclass block-tree-chunker (rag-protocol:rag-chunker)
  ((store :initarg :store :accessor chunker-store :initform nil)))

(defclass block-tree-splitter (block-tree-chunker) ())

(defun make-block-tree-chunker (&key store)
  (make-instance 'block-tree-chunker :store store))

(defun make-block-tree-splitter (&key store)
  (make-instance 'block-tree-splitter :store store))

(defun use-block-tree-chunker (&rest args &key &allow-other-keys)
  (setf rag-protocol:*rag-chunker*
        (apply #'make-block-tree-chunker args)))

(defun %plist-without (plist keys)
  (loop for (k v) on plist by #'cddr
        unless (member k keys :test #'eq)
          append (list k v)))

(defun %body-layer-p (block)
  (eq (or (doc-extract-protocol:block-layer block) :body) :body))

(defun %section-path-string (path)
  (format nil "~{~a~^/~}" (reverse path)))

(defun %bound-slot (object slot-name reader)
  (when (slot-boundp object slot-name)
    (funcall reader object)))

(defun %caption-source-ids (doc)
  (let ((ids '()))
    (dolist (rel (or (doc-extract-protocol:extracted-document-relations doc) nil)
                 ids)
      (when (eq (doc-extract-protocol:block-relation-kind rel) :caption-of)
        (push (doc-extract-protocol:block-relation-from-id rel) ids)))))

(defun %caption-of (doc block)
  (let ((tid (doc-extract-protocol:block-id block)))
    (when tid
      (dolist (rel (or (doc-extract-protocol:extracted-document-relations doc) nil))
        (when (and (eq (doc-extract-protocol:block-relation-kind rel) :caption-of)
                   (equal (doc-extract-protocol:block-relation-to-id rel) tid))
          (let ((src (doc-extract-protocol:find-block
                      doc (doc-extract-protocol:block-relation-from-id rel))))
            (when src
              (return (doc-extract-protocol:block-plain-text src)))))))))

(defun %image-octets (block)
  (%bound-slot block 'doc-extract-protocol::octets
               #'doc-extract-protocol:image-block-octets))

(defun %image-hash (block octets)
  (or (%bound-slot block 'doc-extract-protocol::content-hash
                   #'doc-extract-protocol:image-block-content-hash)
      (when octets
        (doc-extract-protocol:portable-digest octets))))

(defun %store-image (store octets hash)
  "PUT OCTETS at HASH when STORE is non-nil. No-op when STORE is NIL."
  (when (and store octets hash)
    (object-store-protocol:put-object store hash octets)
    t))

(defun %document-id-of (doc)
  (let ((md (and (slot-boundp doc 'doc-extract-protocol::metadata)
                 (doc-extract-protocol:extracted-document-metadata doc))))
    (or (and md (%bound-slot md 'doc-extract-protocol::content-hash
                             #'doc-extract-protocol:document-metadata-content-hash))
        (and md (%bound-slot md 'doc-extract-protocol::filename
                             #'doc-extract-protocol:document-metadata-filename))
        "doc")))

(defun %walk-body (doc store)
  (let ((skip-ids (%caption-source-ids doc))
        (chunks '()))
    (labels ((visit (block path)
               (unless (%body-layer-p block)
                 (return-from visit))
               (let ((id (doc-extract-protocol:block-id block)))
                 (when (and id (member id skip-ids :test #'equal))
                   (return-from visit)))
               (cond
                 ((typep block 'doc-extract-protocol:section)
                  (let ((path (cons (or (doc-extract-protocol:section-title block) "")
                                    path)))
                    (dolist (c (doc-extract-protocol:block-children block))
                      (visit c path))))
                 ((typep block 'doc-extract-protocol:list-block)
                  (dolist (c (doc-extract-protocol:block-children block))
                    (visit c path)))
                 ((typep block 'doc-extract-protocol:table-block)
                  (let* ((md (doc-extract-protocol:render-table block
                                                                :format :markdown))
                         (cap (%caption-of doc block))
                         (text (if (and cap (plusp (length cap)))
                                   (format nil "~a~%~a" md cap)
                                   md)))
                    (push (list :text text
                                :block-id (doc-extract-protocol:block-id block)
                                :section-path (%section-path-string path)
                                :kind :table)
                          chunks)))
                 ((typep block 'doc-extract-protocol:image-block)
                  (let* ((octets (%image-octets block))
                         (hash (%image-hash block octets))
                         (stored (%store-image store octets hash))
                         (text (doc-extract-protocol:block-plain-text block)))
                    (push (list :text text
                                :block-id (doc-extract-protocol:block-id block)
                                :section-path (%section-path-string path)
                                :kind :image
                                :image-ref hash
                                :image-octets (if stored nil octets))
                          chunks)))
                 (t
                  (let ((text (doc-extract-protocol:block-plain-text block)))
                    (when (plusp (length text))
                      (push (list :text text
                                  :block-id (doc-extract-protocol:block-id block)
                                  :section-path (%section-path-string path)
                                  :kind (doc-extract-protocol:block-node-type block))
                            chunks)))))))
      (dolist (b (doc-extract-protocol:extracted-document-blocks doc))
        (visit b '())))
    (nreverse chunks)))

(defun chunk-extracted-document (chunker doc &key document-id base-metadata store)
  "Split EXTRACTED-DOCUMENT DOC into RAG-CHUNKs. STORE (or CHUNKER-STORE)
   receives image octets keyed by content hash; NIL leaves octets inline."
  (check-type chunker block-tree-chunker)
  (check-type doc doc-extract-protocol:extracted-document)
  (let* ((store (or store (chunker-store chunker)))
         (doc-id (or document-id (%document-id-of doc)))
         (base (%plist-without (copy-list base-metadata)
                               '(:extracted-document :store)))
         (parts (%walk-body doc store)))
    (loop for part in parts
          for i from 0
          for bid = (getf part :block-id)
          collect (rag-protocol:make-rag-chunk
                   :id (if bid
                           (format nil "~a:~a" doc-id bid)
                           (format nil "~a:~d" doc-id i))
                   :document-id doc-id
                   :text (or (getf part :text) "")
                   :metadata
                   (append (list :chunk-index i
                                 :block-id bid
                                 :section-path (getf part :section-path)
                                 :kind (getf part :kind))
                           (when (getf part :image-ref)
                             (list :image-ref (getf part :image-ref)))
                           (when (getf part :image-octets)
                             (list :image-octets (getf part :image-octets)))
                           base)))))

(defun %extracted-of (document)
  (let ((ed (getf (rag-protocol:rag-document-metadata document)
                  :extracted-document)))
    (unless (typep ed 'doc-extract-protocol:extracted-document)
      (error 'rag-protocol:rag-error
             :message "block-tree-chunker requires metadata :extracted-document"))
    ed))

(defmethod rag-protocol:chunk :around ((chunker block-tree-chunker) document
                                       &key size overlap)
  (declare (ignore size overlap))
  (if (typep document 'doc-extract-protocol:extracted-document)
      (chunk-extracted-document chunker document)
      (call-next-method)))

(defmethod rag-protocol:chunk ((chunker block-tree-chunker)
                               (document rag-protocol:rag-document)
                               &key size overlap)
  (declare (ignore size overlap))
  (let* ((meta (rag-protocol:rag-document-metadata document))
         (ed (%extracted-of document)))
    (chunk-extracted-document
     chunker ed
     :document-id (rag-protocol:rag-document-id document)
     :base-metadata meta
     :store (or (chunker-store chunker) (getf meta :store)))))
