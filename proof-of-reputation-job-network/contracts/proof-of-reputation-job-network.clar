;; Proof-of-Reputation Job Network Smart Contract
;; A decentralized job marketplace with reputation-based matching

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-job-not-active (err u104))
(define-constant err-already-applied (err u105))
(define-constant err-insufficient-reputation (err u106))
(define-constant err-payment-failed (err u107))
(define-constant err-invalid-status (err u108))
(define-constant err-dispute-exists (err u109))

;; Data Variables
(define-data-var next-job-id uint u1)
(define-data-var next-user-id uint u1)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points
(define-data-var min-reputation-threshold uint u50)

;; Data Maps
(define-map jobs
  { job-id: uint }
  {
    employer: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    budget: uint,
    required-reputation: uint,
    required-skills: (list 5 (string-ascii 50)),
    status: (string-ascii 20), ;; "open", "assigned", "completed", "disputed"
    assigned-freelancer: (optional principal),
    created-at: uint,
    deadline: uint,
    payment-released: bool
  }
)

(define-map job-applications
  { job-id: uint, applicant: principal }
  {
    proposal: (string-ascii 300),
    proposed-budget: uint,
    estimated-duration: uint,
    applied-at: uint,
    status: (string-ascii 20) ;; "pending", "accepted", "rejected"
  }
)

(define-map user-profiles
  { user: principal }
  {
    user-id: uint,
    username: (string-ascii 50),
    reputation-score: uint,
    total-jobs-completed: uint,
    total-earnings: uint,
    skills: (list 10 (string-ascii 50)),
    is-verified: bool,
    created-at: uint
  }
)

(define-map user-reviews
  { reviewer: principal, reviewee: principal, job-id: uint }
  {
    rating: uint, ;; 1-5 stars
    comment: (string-ascii 200),
    skills-rated: (list 5 (string-ascii 50)),
    created-at: uint
  }
)

(define-map escrow-payments
  { job-id: uint }
  {
    amount: uint,
    employer: principal,
    freelancer: principal,
    status: (string-ascii 20), ;; "held", "released", "disputed"
    created-at: uint,
    release-deadline: uint
  }
)

(define-map disputes
  { job-id: uint }
  {
    initiator: principal,
    reason: (string-ascii 300),
    status: (string-ascii 20), ;; "open", "resolved", "closed"
    arbitrator: (optional principal),
    resolution: (optional (string-ascii 300)),
    created-at: uint
  }
)

;; Skill tracking for reputation calculation
(define-map user-skill-ratings
  { user: principal, skill: (string-ascii 50) }
  {
    total-points: uint,
    number-of-ratings: uint,
    average-rating: uint
  }
)

;; Read-only functions
(define-read-only (get-job (job-id uint))
  (map-get? jobs { job-id: job-id })
)

(define-read-only (get-user-profile (user principal))
  (map-get? user-profiles { user: user })
)

(define-read-only (get-job-application (job-id uint) (applicant principal))
  (map-get? job-applications { job-id: job-id, applicant: applicant })
)

(define-read-only (get-user-review (reviewer principal) (reviewee principal) (job-id uint))
  (map-get? user-reviews { reviewer: reviewer, reviewee: reviewee, job-id: job-id })
)

(define-read-only (get-escrow-payment (job-id uint))
  (map-get? escrow-payments { job-id: job-id })
)

(define-read-only (get-dispute (job-id uint))
  (map-get? disputes { job-id: job-id })
)

(define-read-only (get-user-skill-rating (user principal) (skill (string-ascii 50)))
  (map-get? user-skill-ratings { user: user, skill: skill })
)

(define-read-only (calculate-reputation-score (user principal))
  (let
    (
      (profile (unwrap! (get-user-profile user) u0))
      (base-score (get reputation-score profile))
      (jobs-completed (get total-jobs-completed profile))
      (completion-bonus (* jobs-completed u2))
    )
    (+ base-score completion-bonus)
  )
)

;; Public functions

;; User Management
(define-public (create-user-profile (username (string-ascii 50)) (skills (list 10 (string-ascii 50))))
  (let
    (
      (user-id (var-get next-user-id))
      (current-block (stacks-block-height))
    )
    (asserts! (is-none (get-user-profile tx-sender)) err-unauthorized)
    (map-set user-profiles
      { user: tx-sender }
      {
        user-id: user-id,
        username: username,
        reputation-score: u100, ;; Starting reputation
        total-jobs-completed: u0,
        total-earnings: u0,
        skills: skills,
        is-verified: false,
        created-at: current-block
      }
    )
    (var-set next-user-id (+ user-id u1))
    (ok user-id)
  )
)

;; Job Management
(define-public (post-job 
  (title (string-ascii 100))
  (description (string-ascii 500))
  (budget uint)
  (required-reputation uint)
  (required-skills (list 5 (string-ascii 50)))
  (deadline uint))
  (let
    (
      (job-id (var-get next-job-id))
      (current-block (stacks-block-height))
    )
    (asserts! (> budget u0) err-invalid-amount)
    (asserts! (> deadline current-block) err-invalid-amount)
    (asserts! (is-some (get-user-profile tx-sender)) err-unauthorized)
    
    (map-set jobs
      { job-id: job-id }
      {
        employer: tx-sender,
        title: title,
        description: description,
        budget: budget,
        required-reputation: required-reputation,
        required-skills: required-skills,
        status: "open",
        assigned-freelancer: none,
        created-at: current-block,
        deadline: deadline,
        payment-released: false
      }
    )
    (var-set next-job-id (+ job-id u1))
    (ok job-id)
  )
)

(define-public (apply-for-job 
  (job-id uint)
  (proposal (string-ascii 300))
  (proposed-budget uint)
  (estimated-duration uint))
  (let
    (
      (job (unwrap! (get-job job-id) err-not-found))
      (applicant-profile (unwrap! (get-user-profile tx-sender) err-unauthorized))
      (current-block (stacks-block-height))
    )
    (asserts! (is-eq (get status job) "open") err-job-not-active)
    (asserts! (is-none (get-job-application job-id tx-sender)) err-already-applied)
    (asserts! (>= (get reputation-score applicant-profile) (get required-reputation job)) err-insufficient-reputation)
    (asserts! (> proposed-budget u0) err-invalid-amount)
    
    (map-set job-applications
      { job-id: job-id, applicant: tx-sender }
      {
        proposal: proposal,
        proposed-budget: proposed-budget,
        estimated-duration: estimated-duration,
        applied-at: current-block,
        status: "pending"
      }
    )
    (ok true)
  )
)

(define-public (assign-job (job-id uint) (freelancer principal))
  (let
    (
      (job (unwrap! (get-job job-id) err-not-found))
      (application (unwrap! (get-job-application job-id freelancer) err-not-found))
      (current-block (stacks-block-height))
    )
    (asserts! (is-eq tx-sender (get employer job)) err-unauthorized)
    (asserts! (is-eq (get status job) "open") err-job-not-active)
    (asserts! (is-eq (get status application) "pending") err-invalid-status)
    
    ;; Update job status
    (map-set jobs
      { job-id: job-id }
      (merge job {
        status: "assigned",
        assigned-freelancer: (some freelancer)
      })
    )
    
    ;; Update application status
    (map-set job-applications
      { job-id: job-id, applicant: freelancer }
      (merge application { status: "accepted" })
    )
    
    ;; Create escrow payment
    (map-set escrow-payments
      { job-id: job-id }
      {
        amount: (get proposed-budget application),
        employer: tx-sender,
        freelancer: freelancer,
        status: "held",
        created-at: current-block,
        release-deadline: (+ current-block u144) ;; ~24 hours
      }
    )
    
    (ok true)
  )
)

(define-public (complete-job (job-id uint))
  (let
    (
      (job (unwrap! (get-job job-id) err-not-found))
      (assigned-freelancer (unwrap! (get assigned-freelancer job) err-unauthorized))
    )
    (asserts! (is-eq tx-sender assigned-freelancer) err-unauthorized)
    (asserts! (is-eq (get status job) "assigned") err-invalid-status)
    
    (map-set jobs
      { job-id: job-id }
      (merge job { status: "completed" })
    )
    (ok true)
  )
)

(define-public (release-payment (job-id uint))
  (let
    (
      (job (unwrap! (get-job job-id) err-not-found))
      (escrow (unwrap! (get-escrow-payment job-id) err-not-found))
      (freelancer-profile (unwrap! (get-user-profile (get freelancer escrow)) err-not-found))
    )
    (asserts! (is-eq tx-sender (get employer job)) err-unauthorized)
    (asserts! (is-eq (get status job) "completed") err-invalid-status)
    (asserts! (is-eq (get status escrow) "held") err-invalid-status)
    
    ;; Calculate platform fee
    (let
      (
        (payment-amount (get amount escrow))
        (platform-fee (/ (* payment-amount (var-get platform-fee-rate)) u10000))
        (freelancer-payment (- payment-amount platform-fee))
      )
      
      ;; Update escrow status
      (map-set escrow-payments
        { job-id: job-id }
        (merge escrow { status: "released" })
      )
      
      ;; Update job payment status
      (map-set jobs
        { job-id: job-id }
        (merge job { payment-released: true })
      )
      
      ;; Update freelancer profile
      (map-set user-profiles
        { user: (get freelancer escrow) }
        (merge freelancer-profile {
          total-jobs-completed: (+ (get total-jobs-completed freelancer-profile) u1),
          total-earnings: (+ (get total-earnings freelancer-profile) freelancer-payment),
          reputation-score: (+ (get reputation-score freelancer-profile) u10)
        })
      )
      
      (ok freelancer-payment)
    )
  )
)

;; Review and Reputation System
(define-public (submit-review 
  (reviewee principal)
  (job-id uint)
  (rating uint)
  (comment (string-ascii 200))
  (skills-rated (list 5 (string-ascii 50))))
  (let
    (
      (job (unwrap! (get-job job-id) err-not-found))
      (current-block (stacks-block-height))
      (reviewee-profile (unwrap! (get-user-profile reviewee) err-not-found))
    )
    (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-amount)
    (asserts! (is-eq (get status job) "completed") err-invalid-status)
    (asserts! (or 
      (is-eq tx-sender (get employer job))
      (is-eq tx-sender (unwrap! (get assigned-freelancer job) err-unauthorized))
    ) err-unauthorized)
    (asserts! (is-none (get-user-review tx-sender reviewee job-id)) err-unauthorized)
    
    ;; Store review
    (map-set user-reviews
      { reviewer: tx-sender, reviewee: reviewee, job-id: job-id }
      {
        rating: rating,
        comment: comment,
        skills-rated: skills-rated,
        created-at: current-block
      }
    )
    
    ;; Update reviewee's reputation
    (let
      (
        (reputation-change (if (>= rating u4) u5 (if (>= rating u3) u0 (- u0 u5))))
        (new-reputation (+ (get reputation-score reviewee-profile) reputation-change))
      )
      (map-set user-profiles
        { user: reviewee }
        (merge reviewee-profile { reputation-score: new-reputation })
      )
    )
    
    (ok true)
  )
)

;; Dispute Resolution
(define-public (initiate-dispute (job-id uint) (reason (string-ascii 300)))
  (let
    (
      (job (unwrap! (get-job job-id) err-not-found))
      (current-block (stacks-block-height))
    )
    (asserts! (or 
      (is-eq tx-sender (get employer job))
      (is-eq tx-sender (unwrap! (get assigned-freelancer job) err-unauthorized))
    ) err-unauthorized)
    (asserts! (is-none (get-dispute job-id)) err-dispute-exists)
    
    (map-set disputes
      { job-id: job-id }
      {
        initiator: tx-sender,
        reason: reason,
        status: "open",
        arbitrator: none,
        resolution: none,
        created-at: current-block
      }
    )
    
    ;; Update job status
    (map-set jobs
      { job-id: job-id }
      (merge job { status: "disputed" })
    )
    
    (ok true)
  )
)

;; Admin functions
(define-public (set-platform-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-rate u1000) err-invalid-amount) ;; Max 10%
    (var-set platform-fee-rate new-rate)
    (ok true)
  )
)

(define-public (verify-user (user principal))
  (let
    (
      (profile (unwrap! (get-user-profile user) err-not-found))
    )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set user-profiles
      { user: user }
      (merge profile { is-verified: true })
    )
    (ok true)
  )
)