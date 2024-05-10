module hostel_booking::hostel_booking {
    // Imports
    use sui::transfer;
    use sui::object::{self, UID, ID};
    use sui::balance::{self, Balance};
    use sui::coin::{self, Coin};
    use sui::table::{self, Table};
    use std::string::String;

    // Errors
    const E_INSUFFICIENT_FUNDS: u64 = 1;
    const E_INVALID_COIN: u64 = 2;
    const E_NOT_STUDENT: u64 = 3;
    const E_INVALID_ROOM: u64 = 4;
    const E_NOT_INSTITUTION: u64 = 5;
    const E_INVALID_HOSTEL_BOOKING: u64 = 6;

    // HostelBooking Institution 
    struct Institution {
        id: UID,
        name: String,
        student_fees: Table<ID, u64>, // student_id -> fees
        balance: Balance,
        memos: Table<ID, RoomMemo>, // student_id -> memo
        institution: address,
    }

    // Student
    struct Student {
        id: UID,
        name: String,
        student_address: address,
        institution_id: ID,
        balance: Balance,
    }

    // RoomMemo
    struct RoomMemo {
        id: UID,
        room_id: ID,
        semester_payment: u64,
        student_fee: u64, // Minimum fee that the student has to pay
        institution: address,
    }

    // Hostel
    struct HostelRoom {
        id: UID,
        name: String,
        room_size: u64,
        institution: address,
        beds_available: u64,
    }

    // Record of Hostel Booking
    struct BookingRecord {
        id: UID,
        student_id: ID,
        room_id: ID,
        student_address: address,
        institution: address,
        paid_fee: u64,
        semester_payment: u64,
        booking_time: u64,
    }

    // Create a new Institution object 
    public fun create_institution(ctx: &mut TxContext, name: String) {
        let institution = Institution {
            id: object::new(ctx),
            name,
            student_fees: table::new(ctx),
            balance: balance::zero(),
            memos: table::new(ctx),
            institution: tx_context::sender(ctx),
        };

        transfer::share_object(institution);
    }

    // Create a new Student object
    public fun create_student(ctx: &mut TxContext, name: String, institution_address: address) {
        let institution_id = object::id_from_address(institution_address);
        let student = Student {
            id: object::new(ctx),
            name,
            student_address: tx_context::sender(ctx),
            institution_id,
            balance: balance::zero(),
        };

        transfer::share_object(student);
    }

    // Create a memo for a room
    public fun create_room_memo(
        institution: &mut Institution,
        semester_payment: u64,
        student_fee: u64,
        room_name: String,
        room_size: u64,
        beds_available: u64,
        ctx: &mut TxContext,
    ): HostelRoom {
        assert!(institution.institution == tx_context::sender(ctx), E_NOT_INSTITUTION);
        let room = HostelRoom {
            id: object::new(ctx),
            name: room_name,
            room_size,
            institution: institution.institution,
            beds_available,
        };
        let memo = RoomMemo {
            id: object::new(ctx),
            room_id: room.id,
            semester_payment,
            student_fee,
            institution: institution.institution,
        };

        table::add(&mut institution.memos, room.id, memo);

        room
    }

    // Book a room
    public fun book_room(
        institution: &mut Institution,
        student: &mut Student,
        room: &mut HostelRoom,
        room_memo_id: ID,
        ctx: &mut TxContext,
    ): Coin {
        assert!(institution.institution == tx_context::sender(ctx), E_NOT_INSTITUTION);
        assert!(student.institution_id == institution.id, E_NOT_STUDENT);
        assert!(table::contains(&institution.memos, room_memo_id), E_INVALID_HOSTEL_BOOKING);
        assert!(room.institution == institution.institution, E_INVALID_ROOM);
        assert!(room.beds_available > 0, E_INVALID_ROOM);

        let memo = table::get(&institution.memos, room_memo_id);
        let booking_record = BookingRecord {
            id: object::new(ctx),
            student_id: student.id,
            room_id: room.id,
            student_address: student.student_address,
            institution: institution.institution,
            paid_fee: memo.student_fee,
            semester_payment: memo.semester_payment,
            booking_time: clock::timestamp_ms(),
        };

        transfer::public_freeze_object(booking_record);

        let total_pay = memo.student_fee + memo.semester_payment;
        assert!(total_pay <= balance::value(&student.balance), E_INSUFFICIENT_FUNDS);
        let amount_to_pay = coin::take(&mut student.balance, total_pay, ctx);
        let institution_balance = coin::take(&mut institution.balance, total_pay, ctx);
        assert!(coin::value(&amount_to_pay) > 0, E_INVALID_COIN);
        assert!(coin::value(&institution_balance) > 0, E_INVALID_COIN);

        transfer::public_transfer(amount_to_pay, institution.institution);

        table::add(&mut institution.student_fees, student.id, memo.student_fee);
        room.beds_available -= 1;

        table::remove(&mut institution.memos, room_memo_id);

        amount_to_pay
    }

    // Student adding funds to their account
    public fun top_up_student_balance(student: &mut Student, amount: Coin, ctx: &mut TxContext) {
        assert!(student.student_address == tx_context::sender(ctx), E_NOT_STUDENT);
        balance::join(&mut student.balance, coin::into_balance(amount));
    }

    // Get the balance of the institution
    public fun get_institution_balance(institution: &Institution): &Balance {
        &institution.balance
    }

    // Institution can withdraw the balance
    public fun withdraw_funds(institution: &mut Institution, amount: u64, ctx: &mut TxContext) {
        assert!(institution.institution == tx_context::sender(ctx), E_NOT_INSTITUTION);
        assert!(amount <= balance::value(&institution.balance), E_INSUFFICIENT_FUNDS);
        let amount_to_withdraw = coin::take(&mut institution.balance, amount, ctx);
        transfer::public_transfer(amount_to_withdraw, institution.institution);
    }

    // Student Returns the room ownership
    // Only increment the beds available in the room
    public fun return_room(
        institution: &mut Institution,
        student: &mut Student,
        room: &mut HostelRoom,
        ctx: &mut TxContext,
    ) {
        assert!(institution.institution == tx_context::sender(ctx), E_NOT_INSTITUTION);
        assert!(student.institution_id == institution.id, E_NOT_STUDENT);
        assert!(room.institution == institution.institution, E_INVALID_ROOM);

        room.beds_available += 1;
    }
}
