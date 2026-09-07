# rag-backend-text

Recursive character splitter for [`rag-protocol`](https://github.com/egao1980/rag-protocol). Not the protocol — product backends stay in their own repos.

```lisp
(asdf:load-system "rag-backend-text")
(rag-backend-text:use-recursive-character-chunker :size 1000 :overlap 200)

(stack-rag:chunk stack-rag:*rag-chunker*
                 (stack-rag:make-rag-document :id "doc" :text *corpus*))
```

Splits on `"\\n\\n"` → `"\\n"` → space → characters. Size is in CL characters. Overlap must be `<` size. Long unsplittable runs are hard-cut.

Default ingest chunker on a bare `rag-pipeline` is still the protocol passthrough — bind this backend when you want real splits.

Part of [cl-stack](https://github.com/egao1980/cl-stack). Cookbook: [rag.md](https://github.com/egao1980/cl-stack/blob/main/docs/cookbooks/rag.md).

## License

MIT — see [LICENSE](LICENSE).
