#lang racket

(require racket/gui
         math/flonum
         pict3d
         pict3d/private/math/flv3
         profile
         )

(current-pict3d-width 512)
(current-pict3d-height 384)
(current-color "azure")
(current-material '(0.01 0.29 0.7 0.2))

;(: xyz-fun (-> Flonum Flonum FlVector))
(define (xyz-fun x y)
  (let ([x  (+ x (* 0.1 (sin (* (+ x y) 10))))]
        [y  (+ y (* 0.1 (cos (* (+ x y) 10))))])
    (flvector x y (* 1.0 (sin x) (cos y)))))

;(: norm-fun (-> Flonum Flonum FlVector))
(define (norm-fun x y)
  (let ([x  (+ x (* 0.1 (sin (* (+ x y) 10))))]
        [y  (+ y (* 0.1 (cos (* (+ x y) 10))))])
    (flv3normalize (flvector (* -1.0 (cos x) (cos y))
                             (* +1.0 (sin x) (sin y))
                             1.0))))

(define grid-size 64)

(define vss
  (append*
   (for*/list ([xi  (in-range 0 grid-size)]
               [yi  (in-range 0 grid-size)])
     (define x0 (* 0.5 (- xi (* 0.5 grid-size))))
     (define y0 (* 0.5 (- yi (* 0.5 grid-size))))
     (define x1 (+ x0 0.5))
     (define y1 (+ y0 0.5))
     (define v0 (xyz-fun x0 y0))
     (define v1 (xyz-fun x1 y0))
     (define v2 (xyz-fun x1 y1))
     (define v3 (xyz-fun x0 y1))
     ;; Split on shortest diagonal
     (if (< (flv3dist v0 v2)
            (flv3dist v1 v3))
         (values (list (list v0 v1 v2)
                       (list v0 v2 v3)))
         (values (list (list v0 v1 v3)
                       (list v1 v2 v3)))))))

(define ts
  (time
   (append
    (for/list ([vs  (in-list vss)])
      (apply triangle vs)))))

(define lights
  (time
   (append
    
    (list (light '(0 0 2) '(1.0 1.0 0.95) 5))
    
    (for*/list ([xi  (in-range 0 grid-size 8)]
                [yi  (in-range 0 grid-size 8)])
      (define x0 (* 0.5 (- xi (* 0.5 grid-size))))
      (define y0 (* 0.5 (- yi (* 0.5 grid-size))))
      (light (list x0 y0 2) '(1 1 0.95) 2)))))

(define rects
  (time
   (for*/list ([xi  (in-range 1 grid-size 2)]
               [yi  (in-range 1 grid-size 2)])
     (define x0 (* 0.5 (- xi (* 0.5 grid-size))))
     (define y0 (* 0.5 (- yi (* 0.5 grid-size))))
     (define x1 (+ x0 0.5))
     (define y1 (+ y0 0.5))
     (define z (flvector-ref (xyz-fun (* 0.5 (+ x0 x1)) (* 0.5 (+ y0 y1))) 2))
     (define transparent? (= 0 (modulo (+ xi yi) 4)))
     (with-color (if transparent? '(0.2 0.3 1.0 0.5) '(0.2 1.0 0.3 1.0))
       (with-material (if transparent? '(0.1 0.2 0.7 0.1) default-material)
         (rectangle (list x0 y0 (* 0.5 z))
                    (list x1 y1 (+ (* 0.5 z) 1.0))))))))

(define surface
  (time
   (combine (combine* lights)
            (combine* ts)
            (combine* rects))))

(define pict
  (set-basis
   surface
   'camera
   (normal-basis '(20 20 20) '(-1 -1 -1))))

(profile
 (for ([_  (in-range 500)])
   (pict3d->bitmap pict 32 32)))
