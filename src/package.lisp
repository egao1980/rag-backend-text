(defpackage #:rag-backend-text
  (:use #:cl)
  (:export #:recursive-character-chunker
           #:make-recursive-character-chunker
           #:use-recursive-character-chunker
           #:chunker-size
           #:chunker-overlap
           #:chunker-separators))

(in-package #:rag-backend-text)
