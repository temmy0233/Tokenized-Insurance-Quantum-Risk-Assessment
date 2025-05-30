;; Policy Management Contract
;; Handles quantum insurance policies

(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_POLICY_EXISTS (err u301))
(define-constant ERR_POLICY_NOT_FOUND (err u302))
(define-constant ERR_INVALID_PREMIUM (err u303))
(define-constant ERR_POLICY_EXPIRED (err u304))

;; Data structures
(define-map insurance-policies uint {
    policyholder: principal,
    insurer: principal,
    coverage-amount: uint,
    premium-amount: uint,
    quantum-premium-multiplier: uint,
    policy-start: uint,
    policy-end: uint,
    risk-assessment-id: uint,
    status: (string-ascii 20)
})

(define-map policy-payments uint {
    policy-id: uint,
    payment-amount: uint,
    payment-date: uint,
    payment-type: (string-ascii 20)
})

(define-data-var policy-counter uint u0)
(define-data-var payment-counter uint u0)

;; Read-only functions
(define-read-only (get-policy (policy-id uint))
    (map-get? insurance-policies policy-id)
)

(define-read-only (get-payment (payment-id uint))
    (map-get? policy-payments payment-id)
)

(define-read-only (is-policy-active (policy-id uint))
    (match (map-get? insurance-policies policy-id)
        policy (and
            (is-eq (get status policy) "active")
            (>= (get policy-end policy) block-height)
        )
        false
    )
)

;; Public functions
(define-public (create-policy
    (policyholder principal)
    (coverage-amount uint)
    (premium-amount uint)
    (quantum-multiplier uint)
    (duration-blocks uint)
    (risk-assessment-id uint))
    (let ((policy-id (+ (var-get policy-counter) u1)))
        (begin
            (asserts! (> coverage-amount u0) ERR_INVALID_PREMIUM)
            (asserts! (> premium-amount u0) ERR_INVALID_PREMIUM)
            (asserts! (is-none (map-get? insurance-policies policy-id)) ERR_POLICY_EXISTS)

            (map-set insurance-policies policy-id {
                policyholder: policyholder,
                insurer: tx-sender,
                coverage-amount: coverage-amount,
                premium-amount: premium-amount,
                quantum-premium-multiplier: quantum-multiplier,
                policy-start: block-height,
                policy-end: (+ block-height duration-blocks),
                risk-assessment-id: risk-assessment-id,
                status: "active"
            })

            (var-set policy-counter policy-id)
            (ok policy-id)
        )
    )
)

(define-public (pay-premium (policy-id uint) (amount uint))
    (let ((policy (unwrap! (map-get? insurance-policies policy-id) ERR_POLICY_NOT_FOUND))
          (payment-id (+ (var-get payment-counter) u1)))
        (begin
            (asserts! (is-policy-active policy-id) ERR_POLICY_EXPIRED)
            (asserts! (is-eq tx-sender (get policyholder policy)) ERR_UNAUTHORIZED)
            (asserts! (>= amount (get premium-amount policy)) ERR_INVALID_PREMIUM)

            (map-set policy-payments payment-id {
                policy-id: policy-id,
                payment-amount: amount,
                payment-date: block-height,
                payment-type: "premium"
            })

            (var-set payment-counter payment-id)
            (ok payment-id)
        )
    )
)

(define-public (update-policy-status (policy-id uint) (new-status (string-ascii 20)))
    (let ((policy (unwrap! (map-get? insurance-policies policy-id) ERR_POLICY_NOT_FOUND)))
        (begin
            (asserts! (is-eq tx-sender (get insurer policy)) ERR_UNAUTHORIZED)

            (map-set insurance-policies policy-id
                (merge policy { status: new-status })
            )

            (ok true)
        )
    )
)

(define-public (extend-policy (policy-id uint) (additional-blocks uint))
    (let ((policy (unwrap! (map-get? insurance-policies policy-id) ERR_POLICY_NOT_FOUND)))
        (begin
            (asserts! (is-eq tx-sender (get insurer policy)) ERR_UNAUTHORIZED)
            (asserts! (is-policy-active policy-id) ERR_POLICY_EXPIRED)

            (map-set insurance-policies policy-id
                (merge policy { policy-end: (+ (get policy-end policy) additional-blocks) })
            )

            (ok true)
        )
    )
)
