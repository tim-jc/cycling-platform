CREATE TABLE IF NOT EXISTS admin.data_source (

    source_id INT AUTO_INCREMENT PRIMARY KEY,

    source_name VARCHAR(50) NOT NULL,

    source_description VARCHAR(255) NULL,

    is_active BOOLEAN NOT NULL,

    created_at DATETIME NOT NULL

);