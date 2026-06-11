create extension if not exists pgcrypto;

create table if not exists public.users (
    id uuid primary key default gen_random_uuid(),
    email varchar(255) not null unique,
    full_name varchar(50) not null,
    password_hash text not null,
    role varchar(20) not null default 'reader',
    account_status varchar(20) not null default 'pending',
    phone varchar(20),
    address varchar(255),
    joined_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint users_role_check check (role in ('reader', 'librarian', 'admin')),
    constraint users_account_status_check check (account_status in ('pending', 'active', 'disabled')),
    constraint users_full_name_length_check check (length(trim(full_name)) between 1 and 50)
);

create table if not exists public.book_categories (
    id uuid primary key default gen_random_uuid(),
    name varchar(50) not null unique,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint book_categories_name_length_check check (length(trim(name)) between 1 and 50)
);

create table if not exists public.books (
    id uuid primary key default gen_random_uuid(),
    category_id uuid not null references public.book_categories(id) on update cascade on delete restrict,
    title varchar(100) not null,
    author varchar(100) not null,
    publish_year integer not null,
    isbn varchar(17),
    description varchar(255) not null,
    quantity_total integer not null,
    quantity_available integer not null default 0,
    quantity_borrowed integer not null default 0,
    quantity_lost integer not null default 0,
    quantity_damaged integer not null default 0,
    catalog_status varchar(20) not null default 'available',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint books_title_length_check check (length(trim(title)) between 1 and 100),
    constraint books_author_length_check check (length(trim(author)) between 1 and 100),
    constraint books_publish_year_check check (publish_year between 1900 and extract(year from now())::integer),
    constraint books_isbn_format_check check (isbn is null or isbn ~ '^(ISBN[- ]?)?((97[89][- ]?)?[0-9][- 0-9]{8,}[0-9X])$'),
    constraint books_description_length_check check (length(trim(description)) between 1 and 255),
    constraint books_quantity_total_check check (quantity_total > 0),
    constraint books_quantity_non_negative_check check (
        quantity_available >= 0
        and quantity_borrowed >= 0
        and quantity_lost >= 0
        and quantity_damaged >= 0
    ),
    constraint books_quantity_balance_check check (
        quantity_total = quantity_available + quantity_borrowed + quantity_lost + quantity_damaged
    ),
    constraint books_catalog_status_check check (catalog_status in ('available', 'unavailable'))
);

create table if not exists public.borrow_orders (
    id uuid primary key default gen_random_uuid(),
    reader_id uuid not null references public.users(id) on update cascade on delete restrict,
    book_id uuid not null references public.books(id) on update cascade on delete restrict,
    approved_by uuid references public.users(id) on update cascade on delete set null,
    borrow_days integer not null default 14,
    requested_at date not null default current_date,
    approved_at date,
    borrowed_at date,
    due_date date,
    returned_at date,
    renewal_count integer not null default 0,
    status varchar(20) not null default 'pending',
    rejection_reason varchar(255),
    return_condition varchar(20),
    return_note varchar(500),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint borrow_orders_borrow_days_check check (borrow_days between 1 and 30),
    constraint borrow_orders_renewal_count_check check (renewal_count between 0 and 1),
    constraint borrow_orders_status_check check (status in ('pending', 'borrowed', 'overdue', 'returned', 'rejected')),
    constraint borrow_orders_return_condition_check check (
        return_condition is null or return_condition in ('normal', 'damaged', 'lost')
    )
);

create table if not exists public.return_requests (
    id uuid primary key default gen_random_uuid(),
    borrow_order_id uuid not null references public.borrow_orders(id) on update cascade on delete restrict,
    reader_id uuid not null references public.users(id) on update cascade on delete restrict,
    confirmed_by uuid references public.users(id) on update cascade on delete set null,
    status varchar(20) not null default 'pending',
    requested_at date not null default current_date,
    confirmed_at date,
    note varchar(500),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint return_requests_status_check check (status in ('pending', 'confirmed', 'rejected')),
    constraint return_requests_note_length_check check (note is null or length(note) <= 500)
);

create unique index if not exists return_requests_one_pending_per_borrow_order
    on public.return_requests (borrow_order_id)
    where status = 'pending';

create table if not exists public.fine_levels (
    id uuid primary key default gen_random_uuid(),
    name varchar(25) not null,
    amount numeric(12, 2) not null,
    fine_type varchar(20) not null,
    is_active boolean not null default true,
    created_by uuid references public.users(id) on update cascade on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint fine_levels_name_length_check check (length(trim(name)) between 1 and 25),
    constraint fine_levels_amount_check check (amount > 0),
    constraint fine_levels_type_check check (fine_type in ('late', 'damaged', 'lost', 'other'))
);

create table if not exists public.fines (
    id uuid primary key default gen_random_uuid(),
    reader_id uuid not null references public.users(id) on update cascade on delete restrict,
    borrow_order_id uuid references public.borrow_orders(id) on update cascade on delete set null,
    return_request_id uuid references public.return_requests(id) on update cascade on delete set null,
    fine_level_id uuid not null references public.fine_levels(id) on update cascade on delete restrict,
    confirmed_by uuid references public.users(id) on update cascade on delete set null,
    reason varchar(255) not null,
    amount numeric(12, 2) not null,
    status varchar(20) not null default 'unpaid',
    fined_at date not null default current_date,
    paid_submitted_at date,
    confirmed_at date,
    rejection_reason varchar(255),
    note varchar(500),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint fines_amount_check check (amount > 0),
    constraint fines_status_check check (status in ('unpaid', 'pending', 'paid', 'rejected')),
    constraint fines_reason_length_check check (length(trim(reason)) between 1 and 255),
    constraint fines_note_length_check check (note is null or length(note) <= 500)
);

create index if not exists books_category_id_idx on public.books(category_id);
create index if not exists borrow_orders_reader_id_idx on public.borrow_orders(reader_id);
create index if not exists borrow_orders_book_id_idx on public.borrow_orders(book_id);
create index if not exists return_requests_borrow_order_id_idx on public.return_requests(borrow_order_id);
create index if not exists fines_reader_id_idx on public.fines(reader_id);
create index if not exists fines_status_idx on public.fines(status);

alter table public.users enable row level security;
alter table public.book_categories enable row level security;
alter table public.books enable row level security;
alter table public.borrow_orders enable row level security;
alter table public.return_requests enable row level security;
alter table public.fine_levels enable row level security;
alter table public.fines enable row level security;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create or replace trigger set_users_updated_at
before update on public.users
for each row execute function public.set_updated_at();

create or replace trigger set_book_categories_updated_at
before update on public.book_categories
for each row execute function public.set_updated_at();

create or replace trigger set_books_updated_at
before update on public.books
for each row execute function public.set_updated_at();

create or replace trigger set_borrow_orders_updated_at
before update on public.borrow_orders
for each row execute function public.set_updated_at();

create or replace trigger set_return_requests_updated_at
before update on public.return_requests
for each row execute function public.set_updated_at();

create or replace trigger set_fine_levels_updated_at
before update on public.fine_levels
for each row execute function public.set_updated_at();

create or replace trigger set_fines_updated_at
before update on public.fines
for each row execute function public.set_updated_at();

insert into public.users (id, email, full_name, password_hash, role, account_status, phone, address, joined_at)
values
    (
        '11111111-1111-1111-1111-111111111111',
        'reader@example.com',
        'Test Reader',
        crypt('Password123', gen_salt('bf')),
        'reader',
        'active',
        '0900000001',
        'Reader test address',
        now()
    ),
    (
        '22222222-2222-2222-2222-222222222222',
        'librarian@example.com',
        'Test Librarian',
        crypt('Password123', gen_salt('bf')),
        'librarian',
        'active',
        '0900000002',
        'Librarian test address',
        now()
    ),
    (
        '33333333-3333-3333-3333-333333333333',
        'admin@example.com',
        'Test Admin',
        crypt('Password123', gen_salt('bf')),
        'admin',
        'active',
        '0900000003',
        'Admin test address',
        now()
    )
on conflict (email) do update set
    full_name = excluded.full_name,
    password_hash = excluded.password_hash,
    role = excluded.role,
    account_status = excluded.account_status,
    phone = excluded.phone,
    address = excluded.address;

insert into public.book_categories (id, name)
values ('44444444-4444-4444-4444-444444444444', 'Technology')
on conflict (name) do update set
    updated_at = now();

insert into public.books (
    id,
    category_id,
    title,
    author,
    publish_year,
    isbn,
    description,
    quantity_total,
    quantity_available,
    quantity_borrowed,
    quantity_lost,
    quantity_damaged,
    catalog_status
)
values (
    '55555555-5555-5555-5555-555555555555',
    '44444444-4444-4444-4444-444444444444',
    'Clean Code',
    'Robert C Martin',
    2008,
    '9780132350884',
    'A practical guide to writing cleaner software.',
    3,
    2,
    1,
    0,
    0,
    'available'
)
on conflict (id) do update set
    category_id = excluded.category_id,
    title = excluded.title,
    author = excluded.author,
    publish_year = excluded.publish_year,
    isbn = excluded.isbn,
    description = excluded.description,
    quantity_total = excluded.quantity_total,
    quantity_available = excluded.quantity_available,
    quantity_borrowed = excluded.quantity_borrowed,
    quantity_lost = excluded.quantity_lost,
    quantity_damaged = excluded.quantity_damaged,
    catalog_status = excluded.catalog_status;

insert into public.borrow_orders (
    id,
    reader_id,
    book_id,
    approved_by,
    borrow_days,
    requested_at,
    approved_at,
    borrowed_at,
    due_date,
    renewal_count,
    status
)
values (
    '66666666-6666-6666-6666-666666666666',
    '11111111-1111-1111-1111-111111111111',
    '55555555-5555-5555-5555-555555555555',
    '22222222-2222-2222-2222-222222222222',
    14,
    current_date - 3,
    current_date - 2,
    current_date - 2,
    current_date + 12,
    0,
    'borrowed'
)
on conflict (id) do update set
    reader_id = excluded.reader_id,
    book_id = excluded.book_id,
    approved_by = excluded.approved_by,
    borrow_days = excluded.borrow_days,
    requested_at = excluded.requested_at,
    approved_at = excluded.approved_at,
    borrowed_at = excluded.borrowed_at,
    due_date = excluded.due_date,
    renewal_count = excluded.renewal_count,
    status = excluded.status;

insert into public.return_requests (
    id,
    borrow_order_id,
    reader_id,
    confirmed_by,
    status,
    requested_at,
    confirmed_at,
    note
)
values (
    '77777777-7777-7777-7777-777777777777',
    '66666666-6666-6666-6666-666666666666',
    '11111111-1111-1111-1111-111111111111',
    null,
    'pending',
    current_date,
    null,
    'Reader requests to return this book.'
)
on conflict (id) do update set
    borrow_order_id = excluded.borrow_order_id,
    reader_id = excluded.reader_id,
    confirmed_by = excluded.confirmed_by,
    status = excluded.status,
    requested_at = excluded.requested_at,
    confirmed_at = excluded.confirmed_at,
    note = excluded.note;

insert into public.fine_levels (
    id,
    name,
    amount,
    fine_type,
    is_active,
    created_by
)
values (
    '88888888-8888-8888-8888-888888888888',
    'Late return',
    50000,
    'late',
    true,
    '33333333-3333-3333-3333-333333333333'
)
on conflict (id) do update set
    name = excluded.name,
    amount = excluded.amount,
    fine_type = excluded.fine_type,
    is_active = excluded.is_active,
    created_by = excluded.created_by;

insert into public.fines (
    id,
    reader_id,
    borrow_order_id,
    return_request_id,
    fine_level_id,
    confirmed_by,
    reason,
    amount,
    status,
    fined_at,
    paid_submitted_at,
    confirmed_at,
    rejection_reason,
    note
)
values (
    '99999999-9999-9999-9999-999999999999',
    '11111111-1111-1111-1111-111111111111',
    '66666666-6666-6666-6666-666666666666',
    '77777777-7777-7777-7777-777777777777',
    '88888888-8888-8888-8888-888888888888',
    null,
    'Test unpaid fine for late return workflow',
    50000,
    'unpaid',
    current_date,
    null,
    null,
    null,
    'Seed data for reader fine payment flow.'
)
on conflict (id) do update set
    reader_id = excluded.reader_id,
    borrow_order_id = excluded.borrow_order_id,
    return_request_id = excluded.return_request_id,
    fine_level_id = excluded.fine_level_id,
    confirmed_by = excluded.confirmed_by,
    reason = excluded.reason,
    amount = excluded.amount,
    status = excluded.status,
    fined_at = excluded.fined_at,
    paid_submitted_at = excluded.paid_submitted_at,
    confirmed_at = excluded.confirmed_at,
    rejection_reason = excluded.rejection_reason,
    note = excluded.note;
