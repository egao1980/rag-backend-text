(defsystem "rag-backend-text"
  :version "0.2.0"
  :description "Recursive character splitter + block-tree chunker for rag-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ("rag-protocol" "doc-extract-protocol" "object-store-protocol")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "backend")
               (:file "chunker"))
  :in-order-to ((test-op (test-op "rag-backend-text/tests"))))

(defsystem "rag-backend-text/tests"
  :depends-on ("rag-backend-text" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "backend-test")
               (:file "chunker-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
