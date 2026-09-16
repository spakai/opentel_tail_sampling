CREATE TABLE IF NOT EXISTS customer (
    id BIGINT PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);

INSERT INTO customer (id, name) VALUES
    (1, 'Ada Lovelace'),
    (2, 'Grace Hopper'),
    (3, 'Katherine Johnson')
ON CONFLICT (id) DO NOTHING;
