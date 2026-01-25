program private_lending_credit9.aleo {

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
        active: bool,
        loan_type: u8         // 0 = offer, 1 = active, 2 = completed, 3 = cancelled
    }

    // 1. LEND - Create a new loan offer
    transition lend(
        to: address,
        amount: u64,
        interest: u32,
        days: u64
    ) -> Loan {
        let valid: bool = amount > 0u64 && interest <= 5000u32 && days <= 365u64 ? true : false;
        assert_eq(valid, true);
        
        let seconds_per_day: u64 = 86400u64;
        let due_time: u64 = days * seconds_per_day;
        
        return Loan {
            owner: self.caller,    // Lender owns the offer
            lender: self.caller,
            borrower: to,
            amount: amount,
            interest: interest,
            repaid: 0u64,
            due_time: due_time,    // Relative days, will be converted to absolute
            created: 0u64,         // Will be set when accepted
            active: false,
            loan_type: 0u8         // 0 = offer
        };
    }

    // 2. SEND - Lender sends the offer to borrower
    transition send_offer(offer: Loan, to: address) -> Loan {
        // Only lender can send the offer
        assert_eq(offer.owner, self.caller);
        assert_eq(offer.lender, self.caller);
        assert_eq(offer.active, false);
        assert_eq(offer.loan_type, 0u8); // Must be an offer
        
        // Transfer ownership to borrower
        return Loan {
            owner: to,              // Borrower now owns this offer
            lender: offer.lender,
            borrower: to,
            amount: offer.amount,
            interest: offer.interest,
            repaid: offer.repaid,
            due_time: offer.due_time,
            created: offer.created,
            active: false,
            loan_type: 0u8          // Still an offer
        };
    }

    // 3. BORROW - Borrower accepts and activates loan
    transition borrow(offer: Loan, current_time: u64) -> Loan {
        // Check if caller owns the offer (lender sent it to them)
        assert_eq(offer.owner, self.caller);
        assert_eq(offer.borrower, self.caller);
        assert_eq(offer.active, false);
        assert_eq(offer.loan_type, 0u8); // Must be an offer
        
        // Calculate absolute due timestamp
        let absolute_due: u64 = current_time + offer.due_time;
        
        // Activate the loan
        return Loan {
            owner: offer.borrower,  // Borrower owns active loan
            lender: offer.lender,
            borrower: offer.borrower,
            amount: offer.amount,
            interest: offer.interest,
            repaid: 0u64,
            due_time: absolute_due, // Now absolute timestamp
            created: current_time,
            active: true,
            loan_type: 1u8          // 1 = active loan
        };
    }

    // 4. PAY - Make a repayment
    transition pay(loan: Loan, amount: u64, current_time: u64) -> (Loan, Loan) {
        // Check ownership and status
        assert_eq(loan.owner, self.caller);
        assert_eq(loan.active, true);
        assert_eq(loan.loan_type, 1u8); // Must be active loan
        
        // Calculate new values
        let new_repaid: u64 = loan.repaid + amount;
        let total_due: u64 = loan.amount + ((loan.amount * loan.interest as u64) / 10000u64);
        let is_done: bool = new_repaid >= total_due ? true : false;
        
        // Update the loan
        let updated_loan: Loan = Loan {
            owner: loan.owner,
            lender: loan.lender,
            borrower: loan.borrower,
            amount: loan.amount,
            interest: loan.interest,
            repaid: new_repaid,
            due_time: loan.due_time,
            created: loan.created,
            active: is_done ? false : true,
            loan_type: is_done ? 2u8 : 1u8 // 2 = completed if paid off
        };
        
        // Create payment proof for lender
        let payment_proof: Loan = Loan {
            owner: loan.lender,     // Lender gets proof
            lender: loan.lender,
            borrower: loan.borrower,
            amount: amount,
            interest: 0u32,         // No interest on proof
            repaid: amount,
            due_time: current_time,
            created: current_time,
            active: false,
            loan_type: 3u8          // 3 = payment proof
        };
        
        return (updated_loan, payment_proof);
    }

    // 5. CLAIM - Lender claims repayment
    transition claim(payment: Loan, current_time: u64) -> Loan {
        // Verify lender owns this payment proof
        assert_eq(payment.owner, self.caller);
        assert_eq(payment.loan_type, 3u8); // Must be payment proof
        
        // Mark payment as claimed
        return Loan {
            owner: payment.owner,
            lender: payment.lender,
            borrower: payment.borrower,
            amount: payment.amount,
            interest: payment.interest,
            repaid: payment.repaid,
            due_time: payment.due_time,
            created: current_time,  // Update to claim time
            active: false,
            loan_type: 4u8          // 4 = claimed payment
        };
    }

    // 6. EXTEND - Extend loan duration
    transition extend(loan: Loan, extra_days: u64, current_time: u64) -> Loan {
        // Only borrower can extend
        assert_eq(loan.owner, self.caller);
        assert_eq(loan.active, true);
        assert_eq(loan.loan_type, 1u8); // Must be active
        
        // Validate extension
        let valid_extension: bool = extra_days <= 30u64 ? true : false;
        assert_eq(valid_extension, true);
        
        // Calculate new due time with fee
        let seconds_per_day: u64 = 86400u64;
        let extra_seconds: u64 = extra_days * seconds_per_day;
        let fee_days: u64 = extra_days / 10u64;  // 10% fee
        let fee_seconds: u64 = fee_days * seconds_per_day;
        
        let new_due_time: u64 = loan.due_time + extra_seconds + fee_seconds;
        let fee_interest: u32 = (fee_days as u32) * 10u32;
        
        return Loan {
            owner: loan.owner,
            lender: loan.lender,
            borrower: loan.borrower,
            amount: loan.amount,
            interest: loan.interest + fee_interest,
            repaid: loan.repaid,
            due_time: new_due_time,
            created: loan.created,
            active: true,
            loan_type: 1u8          // Still active
        };
    }

    // 7. SPLIT - Split loan into parts
    transition split(loan: Loan, parts: u64) -> (Loan, Loan) {
        // Only borrower can split
        assert_eq(loan.owner, self.caller);
        assert_eq(loan.active, true);
        assert_eq(loan.loan_type, 1u8); // Must be active
        
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
            active: true,
            loan_type: 1u8
        };
        
        // Second part
        let part2: Loan = Loan {
            owner: loan.owner,
            lender: loan.lender,
            borrower: loan.borrower,
            amount: loan.amount - split_amount,
            interest: loan.interest,
            repaid: loan.repaid - split_repaid,
            due_time: loan.due_time,
            created: loan.created,
            active: true,
            loan_type: 1u8
        };
        
        return (part1, part2);
    }

    // 8. SWAP - Transfer loan to another borrower
    transition swap(
        loan: Loan,
        new_borrower: address,
        fee: u64,
        current_time: u64
    ) -> (Loan, Loan) {
        // Only current borrower can swap
        assert_eq(loan.owner, self.caller);
        assert_eq(loan.active, true);
        assert_eq(loan.loan_type, 1u8); // Must be active
        
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
            active: true,
            loan_type: 1u8
        };
        
        // Create fee record for original borrower
        let fee_record: Loan = Loan {
            owner: self.caller,    // Original borrower gets fee
            lender: self.caller,
            borrower: new_borrower,
            amount: fee,
            interest: 0u32,
            repaid: fee,
            due_time: current_time,
            created: current_time,
            active: false,
            loan_type: 5u8         // 5 = fee record
        };
        
        return (new_loan, fee_record);
    }

    // 9. CANCEL - Lender cancels an offer before it's accepted
    transition cancel_offer(offer: Loan) -> Loan {
        assert_eq(offer.owner, self.caller);
        assert_eq(offer.lender, self.caller);
        assert_eq(offer.active, false);
        assert_eq(offer.loan_type, 0u8); // Must be offer
        assert_eq(offer.repaid, 0u64);
        
        // Mark as cancelled
        return Loan {
            owner: offer.owner,
            lender: offer.lender,
            borrower: offer.borrower,
            amount: 0u64,          // Zero amount indicates cancelled
            interest: offer.interest,
            repaid: 0u64,
            due_time: offer.due_time,
            created: offer.created,
            active: false,
            loan_type: 6u8         // 6 = cancelled
        };
    }

    // 10. REJECT - Borrower rejects a received offer
    transition reject_offer(offer: Loan) -> Loan {
        assert_eq(offer.owner, self.caller);
        assert_eq(offer.borrower, self.caller);
        assert_eq(offer.active, false);
        assert_eq(offer.loan_type, 0u8); // Must be offer
        
        // Return offer to lender
        return Loan {
            owner: offer.lender,
            lender: offer.lender,
            borrower: offer.borrower,
            amount: offer.amount,
            interest: offer.interest,
            repaid: 0u64,
            due_time: offer.due_time,
            created: offer.created,
            active: false,
            loan_type: 0u8         // Still an offer
        };
    }

    // 11. LIST_OFFER - Create public loan offer (anyone can accept)
    transition list_offer(
        amount: u64,
        interest: u32,
        days: u64
    ) -> Loan {
        let valid: bool = amount > 0u64 && interest <= 5000u32 && days <= 365u64 ? true : false;
        assert_eq(valid, true);
        
        let seconds_per_day: u64 = 86400u64;
        let due_time: u64 = days * seconds_per_day;
        
        // Public offer - borrower field is lender's address initially
        return Loan {
            owner: self.caller,
            lender: self.caller,
            borrower: self.caller, // Will be replaced by acceptor
            amount: amount,
            interest: interest,
            repaid: 0u64,
            due_time: due_time,
            created: 0u64,
            active: false,
            loan_type: 7u8         // 7 = public offer
        };
    }

    // 12. ACCEPT_PUBLIC_OFFER - Borrower accepts a public listed offer
    transition accept_public_offer(offer: Loan, current_time: u64) -> Loan {
        // Check this is a public offer
        assert_eq(offer.owner, offer.lender); // Still owned by lender
        assert_eq(offer.loan_type, 7u8);      // Must be public offer
        assert_eq(offer.active, false);
        
        let absolute_due: u64 = current_time + offer.due_time;
        
        // Create active loan for borrower
        return Loan {
            owner: self.caller,     // Borrower owns it
            lender: offer.lender,
            borrower: self.caller,  // Borrower is the acceptor
            amount: offer.amount,
            interest: offer.interest,
            repaid: 0u64,
            due_time: absolute_due,
            created: current_time,
            active: true,
            loan_type: 1u8          // Now active loan
        };
    }

    // 13. CHECK - Quick status check
    transition check(loan: Loan, current_time: u64) -> (bool, bool, bool, u8) {
        let is_active: bool = loan.active;
        let is_overdue: bool = current_time > loan.due_time ? true : false;
        let total_due: u64 = loan.amount + ((loan.amount * loan.interest as u64) / 10000u64);
        let is_paid: bool = loan.repaid >= total_due ? true : false;
        
        return (is_active, is_overdue, is_paid, loan.loan_type);
    }

    // 14. CALCULATE - Calculate total due amount
    transition calculate_total(loan: Loan) -> u64 {
        return loan.amount + ((loan.amount * loan.interest as u64) / 10000u64);
    }

    // 15. TIME_LEFT - Calculate remaining time
    transition time_left(loan: Loan, current_time: u64) -> u64 {
        let remaining: u64 = loan.due_time > current_time ? loan.due_time - current_time : 0u64;
        return remaining;
    }

    // 16. PAYMENT_PROGRESS - Show repayment progress
    transition payment_progress(loan: Loan) -> (u64, u64, u64) {
        let total_due: u64 = loan.amount + ((loan.amount * loan.interest as u64) / 10000u64);
        let remaining: u64 = total_due > loan.repaid ? total_due - loan.repaid : 0u64;
        let percentage: u64 = (loan.repaid * 100u64) / total_due;
        
        return (loan.repaid, remaining, percentage);
    }

    // 17. GET_STATUS - Get human-readable status
    transition get_status(loan: Loan) -> u8 {
        return loan.loan_type;
    }

    // 18. UPDATE_INTEREST - Lender updates interest rate on offer
    transition update_interest(offer: Loan, new_interest: u32) -> Loan {
        assert_eq(offer.owner, self.caller);
        assert_eq(offer.lender, self.caller);
        assert_eq(offer.active, false);
        assert_eq(offer.loan_type, 0u8); // Only offers can be updated
        assert_eq(new_interest <= 5000u32, true);
        
        return Loan {
            owner: offer.owner,
            lender: offer.lender,
            borrower: offer.borrower,
            amount: offer.amount,
            interest: new_interest,
            repaid: offer.repaid,
            due_time: offer.due_time,
            created: offer.created,
            active: false,
            loan_type: offer.loan_type
        };
    }
}
