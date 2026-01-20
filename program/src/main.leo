program private_lending_credit.aleo {

    // This is the constructor for the program.
    // The constructor allows you to manage program upgrades.
    // It is called when the program is deployed or upgraded.
    // It is currently configured to **prevent** upgrades.
    // Other configurations include: 
    //  - @admin(address="aleo1...")
    //  - @checksum(mapping="credits.aleo/fixme", key="0field")
    //  - @custom
    // For more information, please refer to the documentation: `https://docs.leo-lang.org/guides/upgradability`
    @noupgrade
    async constructor() {}


    record Loan {
        owner: address,
        lender: address,
        borrower: address,
        amount: u64,
        interest: u32,
        repaid: u64,
        due_time: u64,        // Unix timestamp (seconds)
        created: u64,         // Creation timestamp
        active: bool
    }

    // 1. LEND - Create a new loan offer
    transition lend(
        to: address,
        amount: u64,
        interest: u32,
        days: u64           // Days until due
    ) -> Loan {
        // Validate with cool ternary checks
        let valid: bool = amount > 0u64 && interest <= 5000u32 && days <= 365u64 ? true : false;
        assert_eq(valid, true);
        
        // Calculate due time in seconds (relative)
        let seconds_per_day: u64 = 86400u64;
        let due_time: u64 = days * seconds_per_day;
        
        // Create loan offer
        return Loan {
            owner: self.caller,    // Lender holds offer
            lender: self.caller,
            borrower: to,
            amount: amount,
            interest: interest,
            repaid: 0u64,
            due_time: due_time,    // Relative time from creation
            created: 0u64,         // Will be set when activated
            active: false          // Not active yet
        };
    }

    // 2. BORROW - Accept and activate loan
    transition borrow(offer: Loan, current_time: u64) -> Loan {
        // Check if caller is the intended borrower
        assert_eq(offer.borrower, self.caller);
        
        // Check if offer is still available
        assert_eq(offer.active, false);
        
        // Calculate absolute due timestamp
        let absolute_due: u64 = current_time + offer.due_time;
        
        // Activate the loan with cool flip
        return Loan {
            owner: offer.borrower,      // Borrower now holds active loan
            lender: offer.lender,
            borrower: offer.borrower,
            amount: offer.amount,
            interest: offer.interest,
            repaid: 0u64,
            due_time: absolute_due,     // Now absolute timestamp
            created: current_time,
            active: true                // Now active!
        };
    }

    // 3. PAY - Make a repayment
    transition pay(loan: Loan, amount: u64, current_time: u64) -> (Loan, Loan) {
        // Check ownership and status
        assert_eq(loan.owner, self.caller);
        assert_eq(loan.active, true);
        
        // Calculate new values
        let new_repaid: u64 = loan.repaid + amount;
        let total_due: u64 = loan.amount + ((loan.amount * loan.interest as u64) / 10000u64);
        let is_done: bool = new_repaid >= total_due ? true : false;
        
        // Update borrower's loan
        let updated_loan: Loan = Loan {
            owner: loan.owner,
            lender: loan.lender,
            borrower: loan.borrower,
            amount: loan.amount,
            interest: loan.interest,
            repaid: new_repaid,
            due_time: loan.due_time,
            created: loan.created,
            active: is_done ? false : true  // Deactivate if paid
        };
        
        // Create cool payment proof for lender
        let payment_proof: Loan = Loan {
            owner: loan.lender,          // Lender gets proof
            lender: loan.lender,
            borrower: loan.borrower,
            amount: amount,
            interest: 0u32,              // No interest on proof
            repaid: amount,
            due_time: current_time,      // Use current time
            created: current_time,
            active: false
        };
        
        return (updated_loan, payment_proof);
    }

    // 4. CLAIM - Lender claims repayment
    transition claim(payment: Loan, current_time: u64) -> Loan {
        // Verify lender owns this payment
        assert_eq(payment.owner, self.caller);
        
        // Mark payment as claimed with current time
        return Loan {
            owner: payment.owner,
            lender: payment.lender,
            borrower: payment.borrower,
            amount: payment.amount,
            interest: payment.interest,
            repaid: payment.repaid,
            due_time: payment.due_time,
            created: current_time,  // Update to claim time
            active: false           // Claimed!
        };
    }

    // 5. EXTEND - Extend loan duration
    transition extend(loan: Loan, extra_days: u64, current_time: u64) -> Loan {
        // Only borrower can extend
        assert_eq(loan.owner, self.caller);
        assert_eq(loan.active, true);
        
        // Validate extension
        let valid_extension: bool = extra_days <= 30u64 ? true : false; // Max 30 days
        assert_eq(valid_extension, true);
        
        // Calculate new due time with bonus fee
        let seconds_per_day: u64 = 86400u64;
        let extra_seconds: u64 = extra_days * seconds_per_day;
        let fee_days: u64 = extra_days / 10u64;  // 10% fee
        let fee_seconds: u64 = fee_days * seconds_per_day;
        
        let new_due_time: u64 = loan.due_time + extra_seconds + fee_seconds;
        let fee_interest: u32 = (fee_days as u32) * 10u32;  // Convert to interest points
        
        return Loan {
            owner: loan.owner,
            lender: loan.lender,
            borrower: loan.borrower,
            amount: loan.amount,
            interest: loan.interest + fee_interest,  // Higher interest for extension
            repaid: loan.repaid,
            due_time: new_due_time,
            created: loan.created,
            active: true
        };
    }

    // 6. SPLIT - Split loan into parts
    transition split(loan: Loan, parts: u64) -> (Loan, Loan) {
        // Only borrower can split
        assert_eq(loan.owner, self.caller);
        
        // Validate split
        let can_split: bool = parts > 1u64 && loan.amount >= parts ? true : false;
        assert_eq(can_split, true);
        
        let split_amount: u64 = loan.amount / parts;
        let split_repaid: u64 = loan.repaid / parts;
        
        // First part
        let part1: Loan = Loan {
            owner: loan.owner,
            lender: loan.lender,
            borrower: loan.borrower,
            amount: split_amount,
            interest: loan.interest,
            repaid: split_repaid,
            due_time: loan.due_time,
            created: loan.created,
            active: loan.active
        };
        
        // Second part (rest)
        let part2: Loan = Loan {
            owner: loan.owner,
            lender: loan.lender,
            borrower: loan.borrower,
            amount: loan.amount - split_amount,
            interest: loan.interest,
            repaid: loan.repaid - split_repaid,
            due_time: loan.due_time,
            created: loan.created,
            active: loan.active
        };
        
        return (part1, part2);
    }

    // 7. SWAP - Transfer loan to another borrower
    transition swap(
        loan: Loan,
        new_borrower: address,
        fee: u64,
        current_time: u64
    ) -> (Loan, Loan) {
        // Only current borrower can swap
        assert_eq(loan.owner, self.caller);
        assert_eq(loan.active, true);
        
        // Create new loan for new borrower
        let new_loan: Loan = Loan {
            owner: new_borrower,
            lender: loan.lender,
            borrower: new_borrower,
            amount: loan.amount,
            interest: loan.interest,
            repaid: loan.repaid,
            due_time: loan.due_time,
            created: current_time,  // Reset creation time
            active: true
        };
        
        // Create fee record for original borrower
        let fee_record: Loan = Loan {
            owner: self.caller,          // Original borrower gets fee
            lender: self.caller,
            borrower: new_borrower,
            amount: fee,
            interest: 0u32,
            repaid: fee,
            due_time: current_time,
            created: current_time,
            active: false
        };
        
        return (new_loan, fee_record);
    }

    // 8. CHECK - Quick status check
    transition check(loan: Loan, current_time: u64) -> (bool, bool, bool) {
        // Calculate statuses
        let is_active: bool = loan.active;
        let is_overdue: bool = current_time > loan.due_time ? true : false;
        let total_due: u64 = loan.amount + ((loan.amount * loan.interest as u64) / 10000u64);
        let is_paid: bool = loan.repaid >= total_due ? true : false;
        
        return (is_active, is_overdue, is_paid);
    }

    // 9. RATE - Calculate current rate
    transition rate(loan: Loan, current_time: u64) -> u32 {
        // Only lender or borrower can check rate
        let can_check: bool = self.caller == loan.lender || self.caller == loan.borrower ? true : false;
        assert_eq(can_check, true);
        
        // Add penalty if overdue
        let penalty: u32 = current_time > loan.due_time ? 500u32 : 0u32;  // 5% penalty
        
        return loan.interest + penalty;
    }

    // 10. MIRROR - Create mirror record for backup
    transition mirror(loan: Loan, current_time: u64) -> Loan {
        // Create identical backup record with current time
        return Loan {
            owner: self.caller,
            lender: loan.lender,
            borrower: loan.borrower,
            amount: loan.amount,
            interest: loan.interest,
            repaid: loan.repaid,
            due_time: loan.due_time,
            created: current_time,  // New creation time for mirror
            active: loan.active
        };
    }

    // 11. CALCULATE - Calculate total due amount
    transition calculate_total(loan: Loan) -> u64 {
        // Simple calculation of total due
        return loan.amount + ((loan.amount * loan.interest as u64) / 10000u64);
    }

    // 12. TIME_LEFT - Calculate remaining time
    transition time_left(loan: Loan, current_time: u64) -> u64 {
        // Calculate seconds remaining
        let remaining: u64 = loan.due_time > current_time ? loan.due_time - current_time : 0u64;
        return remaining;
    }

    // 13. DAYS_LEFT - Calculate remaining days
    transition days_left(loan: Loan, current_time: u64) -> u64 {
        let seconds_per_day: u64 = 86400u64;
        let remaining_seconds: u64 = loan.due_time > current_time ? loan.due_time - current_time : 0u64;
        let days: u64 = remaining_seconds / seconds_per_day;
        
        // Add 1 if there's a remainder (partial day)
        let has_remainder: bool = (remaining_seconds % seconds_per_day) > 0u64 ? true : false;
        return has_remainder ? days + 1u64 : days;
    }

    // 14. PAYMENT_PROGRESS - Show repayment progress
    transition payment_progress(loan: Loan) -> (u64, u64, u64) {
        let total_due: u64 = loan.amount + ((loan.amount * loan.interest as u64) / 10000u64);
        let remaining: u64 = total_due > loan.repaid ? total_due - loan.repaid : 0u64;
        let percentage: u64 = (loan.repaid * 100u64) / total_due;
        
        return (loan.repaid, remaining, percentage);
    }
}
