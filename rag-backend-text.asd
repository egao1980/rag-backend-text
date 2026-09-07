(defsystem "rag-backend-text"
  :version "0.1.0"
  :description "Recursive character splitter for rag-protocol"
  :author "egao1980"
  :license "MIT"
  :depends-on ("rag-protocol")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "backend"))
  :in-order-to ((test-op (test-op "rag-backend-text/tests"))))

(defsystem "rag-backend-text/tests"
  :depends-on ("rag-backend-text" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "backend-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
