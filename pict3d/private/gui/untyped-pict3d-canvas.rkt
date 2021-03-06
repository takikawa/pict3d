#lang racket/base

(require racket/match
         racket/gui
         racket/class
         racket/async-channel
         racket/math
         math/flonum
         "../math/flt3.rkt"
         "../engine/scene.rkt"
         "../gl.rkt"
         "parameters.rkt"
         "pict3d-struct.rkt"
         )

(provide pict3d-canvas%)

;; ===================================================================================================
;; Rendering threads

(struct render-command
  (pict3d width height z-near z-far fov-degrees background ambient-color ambient-intensity)
  #:transparent)

#;
(struct render-command ([pict3d : Pict3D]
                        [width : Index]
                        [height : Index]
                        [z-near : Positive-Flonum]
                        [z-far : Positive-Flonum]
                        [fov-degrees : Positive-Flonum]
                        [background : FlVector]
                        [ambient-color : FlVector]
                        [ambient-intensity : Flonum]
                        ) #:transparent)

(define (render cmd canvas)
  (match-define (render-command pict width height
                                znear zfar fov-degrees
                                background ambient-color ambient-intensity)
    cmd)
  ;; Get the view matrix
  (define view (pict3d-view-transform pict))
  ;; Compute the projection matrix
  (define fov-radians (degrees->radians fov-degrees))
  (define proj (perspective-flt3/viewport (fl width) (fl height) fov-radians znear zfar))
  
  ;; Lock everything up for drawing
  (call-with-gl-context
   (λ ()
     ;; Draw the scene and swap buffers
     (draw-scene (pict3d-scene pict) width height
                 view proj
                 background ambient-color ambient-intensity)
     (gl-swap-buffers))
   (send canvas get-managed-gl-context)))

;(: make-canvas-render-thread (-> (Instance Pict3D-Canvas%) (Async-Channelof render-command) Thread))
(define (make-canvas-render-thread canvas ch)
  ;(: render-thread-loop (-> Void))
  (define (render-thread-loop)
    ;; Wait for a scene and view matrix
    ;(: cmd render-command)
    (define cmd
      (let ([cmd  (async-channel-get ch)])
        ;; Empty the queue looking for the lastest one
        (let loop ([cmd  cmd])
          (define new-cmd (async-channel-try-get ch))
          (if new-cmd (loop new-cmd) cmd))))
    
    (render cmd canvas)
    (render-thread-loop))
  
  (thread render-thread-loop))

;; ===================================================================================================
;; Scene canvas

;(: pict3d-canvas% Pict3D-Canvas%)
(define pict3d-canvas%
  (class canvas%
    (init parent
          [style  '()]
          [label  #f]
          [enabled  #t]
          [vert-margin   0]
          [horiz-margin  0]
          [min-width   #f]
          [min-height  #f]
          [stretchable-width   #t]
          [stretchable-height  #t])
    (init-field [pict  empty-pict3d])
    
    (define config (new gl-config%))
    
    (super-new [parent parent]
               [style  (list* 'gl 'no-autoclear style)]
               [paint-callback  void]
               [label  label]
               [gl-config  config]
               [enabled  enabled]
               [vert-margin   vert-margin]
               [horiz-margin  horiz-margin]
               [min-width   min-width]
               [min-height  min-height]
               [stretchable-width   stretchable-width]
               [stretchable-height  stretchable-height])
    
    (define async-updates? #t)
    
    (define/public (set-async-updates? async?)
      (set! async-updates? async?))
    
    ;(: render-queue (Async-Channel render-command))
    (define render-queue (make-async-channel))
    
    ;(: render-thread Thread)
    (define render-thread (make-canvas-render-thread this render-queue))
    
    ;(: last-width (U #f Index))
    ;(: last-height (U #f Index))
    (define last-width #f)
    (define last-height #f)
    
    ;(: get-gl-window-size (-> (Values Index Index)))
    (define (get-gl-window-size)
      (define-values (w h) (send (send this get-dc) get-size))
      (values (exact-floor w)
              (exact-floor h)))
    
    ;(: z-near Positive-Flonum)
    ;(: z-far Positive-Flonum)
    ;(: fov-degrees Positive-Flonum)
    ;(: background FlVector)
    ;(: ambient-color FlVector)
    ;(: ambient-intensity Flonum)
    (define z-near (current-pict3d-z-near))
    (define z-far (current-pict3d-z-far))
    (define fov-degrees (current-pict3d-fov-degrees))
    (define background (current-pict3d-background))
    (define ambient-color (current-pict3d-ambient-color))
    (define ambient-intensity (current-pict3d-ambient-intensity))
    
    (define/public (set-pict3d new-pict)
      (set! pict new-pict)
      (define-values (width height) (get-gl-window-size))
      (set! last-width width)
      (set! last-height height)
      (set! z-near (current-pict3d-z-near))
      (set! z-far (current-pict3d-z-far))
      (set! fov-degrees (current-pict3d-fov-degrees))
      (set! background (current-pict3d-background))
      (set! ambient-color (current-pict3d-ambient-color))
      (set! ambient-intensity (current-pict3d-ambient-intensity))
      (if async-updates?
          (async-channel-put
           render-queue
           (render-command new-pict width height
                           z-near z-far fov-degrees
                           background ambient-color ambient-intensity))
          (render (render-command new-pict width height
                                  z-near z-far fov-degrees
                                  background ambient-color ambient-intensity)
                  this)))
    
    (define/public (get-pict3d) pict)
    
    ;(: managed-ctxt (U #f GL-Context))
    (define managed-ctxt #f)
    
    ;(: get-managed-gl-context (-> GL-Context))
    (define/public (get-managed-gl-context)
      (define mctxt managed-ctxt)
      (cond [mctxt  mctxt]
            [else
             (define ctxt (send (send this get-dc) get-gl-context))
             (cond [(or (not ctxt) (not (send ctxt ok?)))
                    (error 'pict3d-canvas% "no GL context is available")]
                   [else
                    (let ([mctxt  (managed-gl-context ctxt)])
                      (set! managed-ctxt mctxt)
                      mctxt)])]))
    
    (define/override (on-paint)
      (define-values (width height) (get-gl-window-size))
      (when (not (and (equal? width last-width)
                      (equal? height last-height)))
        (set! last-width width)
        (set! last-height height)
        (if async-updates?
            (async-channel-put
             render-queue
             (render-command pict width height
                             z-near z-far fov-degrees
                             background ambient-color ambient-intensity))
            (render (render-command pict width height
                                    z-near z-far fov-degrees
                                    background ambient-color ambient-intensity)
                    this))))
    ))
