;; Claim Processing Contract
;; Manages quantum insurance claims

(define-constant ERR_UNAUTHORIZED (err u400))
(define-constant ERR_CLAIM_EXISTS (err u401))
(define-constant ERR_CLAIM_NOT_FOUND (err u402))
(define-constant ERR_INVALID_AMOUNT (err u403))
(define-constant ERR_POLICY_INACTIVE (err u404))
(define-constant ERR_CLAIM_ALREADY_PROCESSED (err u405))

;; Data structures
(define-map insurance-claims uint {
    claimant: principal,
    policy-id: uint,
    claim-amount: uint,
    quantum-incident-type: (string-ascii 50),
    incident-date: uint,
    claim-date: uint,
    status: (string-ascii 20),
    assessor: (optional principal),
    payout-amount: uint
})

(define-map claim-evidence uint {
    claim-id: uint,
    evidence-hash: (buff 32),
    quantum-signature: (buff 64),
    verification-status: bool
})

(define-data-var claim-counter uint u0)

;; Read-only functions
(define-read-only (get-claim (claim-id uint))
    (map-get? insurance-claims claim-id)
)

(define-read-only (get-claim-evidence (claim-id uint))
    (map-get? claim-evidence claim-id)
)

(define-read-only (calculate-quantum-payout (base-amount uint) (quantum-factor uint))
    (let ((multiplier (if (<= quantum-factor u30) u120 ;; 1.2x for low quantum incidents
                      (if (<= quantum-factor u70) u100 ;; 1.0x for medium quantum incidents
                          u80)))) ;; 0.8x for high quantum incidents
        (/ (* base-amount multiplier) u100)
    )
)

;; Public functions
(define-public (file-claim
    (policy-id uint)
    (claim-amount uint)
    (incident-type (string-ascii 50))
    (incident-date uint)
    (evidence-hash (buff 32))
    (quantum-signature (buff 64)))
    (let ((claim-id (+ (var-get claim-counter) u1)))
        (begin
            (asserts! (> claim-amount u0) ERR_INVALID_AMOUNT)
            (asserts! (is-none (map-get? insurance-claims claim-id)) ERR_CLAIM_EXISTS)

            (map-set insurance-claims claim-id {
                claimant: tx-sender,
                policy-id: policy-id,
                claim-amount: claim-amount,
                quantum-incident-type: incident-type,
                incident-date: incident-date,
                claim-date: block-height,
                status: "pending",
                assessor: none,
                payout-amount: u0
            })

            (map-set claim-evidence claim-id {
                claim-id: claim-id,
                evidence-hash: evidence-hash,
                quantum-signature: quantum-signature,
                verification-status: false
            })

            (var-set claim-counter claim-id)
            (ok claim-id)
        )
    )
)

(define-public (assign-assessor (claim-id uint) (assessor principal))
    (let ((claim (unwrap! (map-get? insurance-claims claim-id) ERR_CLAIM_NOT_FOUND)))
        (begin
            (asserts! (is-eq (get status claim) "pending") ERR_CLAIM_ALREADY_PROCESSED)

            (map-set insurance-claims claim-id
                (merge claim {
                    assessor: (some assessor),
                    status: "under-review"
                })
            )

            (ok true)
        )
    )
)

(define-public (verify-evidence (claim-id uint) (is-valid bool))
    (let ((claim (unwrap! (map-get? insurance-claims claim-id) ERR_CLAIM_NOT_FOUND))
          (evidence (unwrap! (map-get? claim-evidence claim-id) ERR_CLAIM_NOT_FOUND)))
        (begin
            (asserts! (is-eq (some tx-sender) (get assessor claim)) ERR_UNAUTHORIZED)

            (map-set claim-evidence claim-id
                (merge evidence { verification-status: is-valid })
            )

            (ok true)
        )
    )
)

(define-public (process-claim (claim-id uint) (approved bool) (payout-amount uint))
    (let ((claim (unwrap! (map-get? insurance-claims claim-id) ERR_CLAIM_NOT_FOUND)))
        (begin
            (asserts! (is-eq (some tx-sender) (get assessor claim)) ERR_UNAUTHORIZED)
            (asserts! (is-eq (get status claim) "under-review") ERR_CLAIM_ALREADY_PROCESSED)

            (map-set insurance-claims claim-id
                (merge claim {
                    status: (if approved "approved" "denied"),
                    payout-amount: (if approved payout-amount u0)
                })
            )

            (ok true)
        )
    )
)

(define-public (appeal-claim (claim-id uint) (appeal-reason (string-ascii 100)))
    (let ((claim (unwrap! (map-get? insurance-claims claim-id) ERR_CLAIM_NOT_FOUND)))
        (begin
            (asserts! (is-eq tx-sender (get claimant claim)) ERR_UNAUTHORIZED)
            (asserts! (is-eq (get status claim) "denied") ERR_CLAIM_ALREADY_PROCESSED)

            (map-set insurance-claims claim-id
                (merge claim { status: "appeal-pending" })
            )

            (ok true)
        )
    )
)
