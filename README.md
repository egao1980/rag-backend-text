# rag-backend-text

Chunkers for [`rag-protocol`](https://github.com/egao1980/rag-protocol). Not the protocol — product backends stay in their own repos. Version **0.2.0**.

## Recursive character splitter

```lisp
(asdf:load-system "rag-backend-text")
(rag-backend-text:use-recursive-character-chunker :size 1000 :overlap 200)

(stack-rag:chunk stack-rag:*rag-chunker*
                 (stack-rag:make-rag-document :id "doc" :text *corpus*))
```

Splits on `"\\n\\n"` → `"\\n"` → space → characters. Size is in CL characters. Overlap must be `<` size. Long unsplittable runs are hard-cut.

Default ingest chunker on a bare `rag-pipeline` is still the protocol passthrough — bind this backend when you want real splits.

## Block-tree chunker (`block-tree-chunker` / `block-tree-splitter`)

Walks `:body` blocks of a [`doc-extract-protocol`](https://github.com/egao1980/doc-extract-protocol) `extracted-document`. Furniture (`:layer :furniture`) is skipped. A `table-block` is one chunk: `render-table` markdown plus any `caption-of` caption. Every chunk metadata has `:block-id` and `:section-path` so citations resolve with `find-block`.

```lisp
(let* ((doc (stack-doc-extract:extract-document backend source :format :pdf))
       (chunker (rag-backend-text:make-block-tree-chunker)))
  (rag-backend-text:chunk-extracted-document chunker doc)
  ;; or via rag-document metadata
  (stack-rag:chunk chunker
                   (stack-rag:make-rag-document
                    :id "doc"
                    :text (stack-doc-extract:document-text doc)
                    :metadata (list :extracted-document doc))))
```

Image octets: pass an [`object-store-protocol`](https://github.com/egao1980/object-store-protocol) store on the chunker (`:store`), on `chunk-extracted-document` (`:store`), or in document metadata (`:store`). When non-nil, octets are `put-object`'d keyed by content hash and the chunk keeps `:image-ref`. When `store` is nil the dependency is a no-op and octets stay inline on the chunk (`:image-octets`).

Part of [cl-stack](https://github.com/egao1980/cl-stack). Cookbook: [rag.md](https://github.com/egao1980/cl-stack/blob/main/docs/cookbooks/rag.md).

## License

MIT — see [LICENSE](LICENSE).
