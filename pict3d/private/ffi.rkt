#lang s-exp typed-racket/base-env/extra-env-lang

(require (only-in ffi/unsafe ptr-set!)
         (only-in ffi/cvector cvector-set!)
         (only-in ffi/unsafe/cvector make-cvector*)
         (only-in racket/unsafe/ops unsafe-u16vector-set!)
         typed/racket/base
         typed/opengl/ffi-types
         "ffi-types.rkt"
         (for-syntax (submod typed/opengl/ffi-types #%type-decl))
         (for-syntax (submod "ffi-types.rkt" #%type-decl)))

(provide CVector cvector?)

(type-environment
 [ptr-set!  (parse-type #'(-> CPointer CType Integer Any Void))]
 [make-cvector*  (parse-type #'(-> CPointer CType Integer CVector))]
 [cvector-set!  (parse-type #'(-> CVector Integer Any Void))]
 [unsafe-u16vector-set!  (parse-type #'(-> U16Vector Fixnum Fixnum Void))]
 )
