# Connecting to the MySQL instance

```bash
sudo -u dbpoffbzii mysql \
  --socket=/db/p/offbzii/v1/admin/OFFBZIIP1/cfg/OFFBZIIP1mysql.sock

sudo mysql \
  --socket=/db/p/offbzii/v1/admin/OFFBZIIP1/cfg/OFFBZIIP1mysql.sock \
  -u root


\! clear                                                            | Used to clear your terminal in SQL. 
```

## Check which server you are connected to using below command-

```bash
Select @@hostname AS hostname, @@port AS port, VERSION() AS version, @@server_id AS server_id;

Output: 

+----------------------------+------+---------------------+-----------+
| hostname                   | port | version             | server_id |
+----------------------------+------+---------------------+-----------+
| np-mariadb-lvmv9-master001 | 3306 | 10.6.28-MariaDB-log | 890413550 |
+----------------------------+------+---------------------+-----------+

```

Show DATABASES;   | Would give or show you a list of all default/created databases.

+--------------------+
| Database           |
+--------------------+
| dba_audit          |
| dbadb              |
| information_schema |
| mysql              |
| performance_schema |
| sys                |       |
+--------------------+

Database                      Purpose                                                                             Default?

information_schema            Metadata about databases, tables, columns, privileges, etc.                         Yes
mySQL                         System tables for users, privileges, roles and server configuration                 Yes
performance_schema            Runtime performance and instrumentation data                                        Yes
Sys                           Convenient views for performance diagnostics                                        Yes
dba_audit                     Potentially auditing or DBA-related data                                            Custom/optional
dbadb                         Potentially DBA administration objects and metadata                                 Custom/optional

### The four system databases

## information_schema

- This is a virtual metadata database. It lets you inspect the structure of your MariaDB server using SQL, rather than directly reading internal files. Example commands:

```bash
USE information_schema; SHOW TABLES;        | Would output tables in the information_schema database. 
```

## mySQL

- This is the server's internal system database. It stores important information used for authentication, access control and other server features. Unlike information_schema, it contains physical system tables. Example command

```bash
USE mysql;
SHOW TABLES;                            | Would show you the tables in the mysql database. 

SELECT User, Host
FROM mysql.user;                        | Would select and show users and hosts from the mysql user table. 

SHOW GRANTS FOR CURRENT_USER();         | Would show the grants / priviledges for current user root. 
```

## performance_schema

- This database exposes instrumentation about what the server is doing: statement execution, waits, locks, stages and other performance events. It is primarily intended for diagnostics and tuning. Example command

```bash
USE performance_schema;
SHOW TABLES;
```

## sys

- The sys database provides convenient views and helper routines that make performance information easier to interpret. It often presents information from performance_schema in a more readable form. Example command

```bash
USE sys;
SHOW FULL TABLES;

SELECT *
FROM sys.version;         | Would output the sys_version of the mysql database. 
```

MariaDB [sys]> show engines;

+--------------------+---------+-------------------------------------------------------------------------------------------------+--------------+------+------------+
| Engine             | Support | Comment                                                                                         | Transactions | XA   | Savepoints |
+--------------------+---------+-------------------------------------------------------------------------------------------------+--------------+------+------------+
| CSV                | YES     | Stores tables as CSV files                                                                      | NO           | NO   | NO         |
| MRG_MyISAM         | YES     | Collection of identical MyISAM tables                                                           | NO           | NO   | NO         |
| MEMORY             | YES     | Hash based, stored in memory, useful for temporary tables                                       | NO           | NO   | NO         |
| Aria               | YES     | Crash-safe tables with MyISAM heritage. Used for internal temporary tables and privilege tables | NO           | NO   | NO         |
| MyISAM             | YES     | Non-transactional engine with good performance and small data footprint                         | NO           | NO   | NO         |
| SEQUENCE           | YES     | Generated tables filled with sequential values                                                  | YES          | NO   | YES        |
| InnoDB             | DEFAULT | Supports transactions, row-level locking, foreign keys and encryption for tables                | YES          | YES  | YES        |
| PERFORMANCE_SCHEMA | YES     | Performance Schema                                                                              | NO           | NO   | NO         |
+--------------------+---------+-------------------------------------------------------------------------------------------------+--------------+------+------------+

Column                                                  Meaning

Engine                                                  Name of storage engine
Support                                                 Whether it is available, disabled or the default engine.
Comment                                                 Description of its intended purpose.
Transactions                                            Whether it supports transactional operations such as commit and rollback.
XA                                                      Whether it supports XA Distributed transactions.
Savepoints                                              Whether transactions can use savepoints for partial roll back.

- SHOW ENGINES tells you which storage engines your server supports, what each one does, and which engine MariaDB uses by default.
- The output shows DEFAULT for InnoDB, which means a table created without an explicit ENGINE clause will normally use InnoDB.

## The 8 storage engines in our cluster

## InnoDB

- InnoDB is the default transactional storage engine used by MariaDB for workloads that require reliability, consistency, and crash recovery.
- It is designed to support ACID-compliant transactions, high-concurrency access, and referential integrity, making it the standard choice for most production database applications.
- InnoDB is the primary transactional storage engine. It supports ACID transactions, row-level locking, foreign keys, crash recovery and indexes

- Common use cases

InnoDB is well suited for applications where data integrity and concurrent access are priorities. Typical deployments include e-commerce platforms, financial systems, content management systems, customer relationship management (CRM) software, and other business applications that require transactional guarantees, foreign key enforcement, and dependable recovery after failures.

Key features

- Transactions with BEGIN, COMMIT and ROLLBACK.
- Row-level locking, allowing concurrent changes to different rows.
- Foreign keys to enforce relationships between tables.
- Crash recovery using redo and undo mechanisms.
- Multi-version concurrency control (MVCC) for consistent reads. Example

```bash
CREATE TABLE accounts (
    id INT PRIMARY KEY,
    balance DECIMAL(10,2)
) ENGINE=InnoDB;

INSERT INTO accounts VALUES
    (1, 1000.00),
    (2, 500.00);

START TRANSACTION;

UPDATE accounts
SET balance = balance - 100
WHERE id = 1;

UPDATE accounts
SET balance = balance + 100
WHERE id = 2;

COMMIT;
```

- If you replace COMMIT with ROLLBACK, both changes are undone.

## MyISAM

- MyISAM is an older storage engine that uses table-level locking and does not support transactions or foreign keys.
- It can be useful for understanding legacy MySQL databases, but is generally not the choice for new applications.

Key Features

- Table-level locking.
- No transaction rollback.
- No foreign-key enforcement.
- Historically used for read-heavy workloads.

```bash
CREATE TABLE legacy_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    message VARCHAR(255),
    created_at DATETIME
) ENGINE=MyISAM;

INSERT INTO legacy_logs (message, created_at)
VALUES ('Application started', NOW());
```

## Aria

- Aria is a crash-recoverable, non-transactional engine developed for MariaDB. It has similarities to MyISAM but includes recovery mechanisms and is used for certain internal tables and temporary-table operations.

## When it is used

- Aria is well suited for workloads where high concurrency through row-level transactions is not required. It is commonly chosen for:

Read-heavy datasets.
Temporary or intermediate tables.
Applications that previously relied on MyISAM but benefit from improved recovery.
Internal MariaDB operations involving temporary storage.

Key features

- Crash recovery through logging.
- Table-level locking.
- No normal transactional rollback.
- Can be useful for internal and temporary data. Example

```bash
CREATE TABLE import_stage (
    id INT,
    raw_value VARCHAR(255)
) ENGINE=Aria;

INSERT INTO import_stage
VALUES (1, 'temporary imported record');

SHOW TABLE STATUS
LIKE 'import_stage';
```

- Important: Crash-safe does not mean transactional. Aria's recovery capabilities do not make it equivalent to InnoDB.

## Memory

- MEMORY stores table data in RAM rather than persisting it as ordinary table data on disk. It can be useful for small, temporary datasets that need fast access.

Key features

- Data held in memory.
- Data disappears when the server restarts.
- No transactions or foreign keys.
- Memory consumption increases with the amount of data. Example

## Typical use cases

- The engine is most appropriate when durability is unnecessary and performance is the primary goal. Common scenarios include:
- Application caches that can be regenerated from persistent tables.
- Temporary work areas used during data transformation or reporting.
- Fast lookup tables containing small, frequently accessed datasets.

Intermediate processing before results are written to a persistent storage engine such as InnoDB.

```bash
CREATE TABLE session_cache (
    session_id VARCHAR(50) PRIMARY KEY,
    username VARCHAR(100)
) ENGINE=MEMORY;

INSERT INTO session_cache
VALUES ('abc123', 'paul');

SELECT * FROM session_cache;
```

- When to use it: Temporary caches, small lookup data and workloads where data can be regenerated.
- Galera note: MEMORY data is local and volatile. Do not assume its contents will be replicated to the other nodes.

## CSV

- CSV stores table data in comma-separated value files. It is useful for simple data exchange, but lacks the indexing, transactional and relational capabilities expected of a general-purpose database engine.
- CSV is a storage engine for MariaDB that stores each table as plain comma-separated values (CSV) text files instead of a binary database format.
- It is primarily intended for data interchange and simple inspection, making it easy to exchange table data with other applications that understand the CSV format, though it lacks many features expected from transactional database engines.

Key features

- Data stored in CSV format.
- No transactions.
- No indexes in the usual sense.
- Convenient for simple import/export scenarios. Example
- The CSV engine is best suited for temporary exchange tables, data exports, simple reporting pipelines, or environments where human-readable storage is valuable.
- It is generally not recommended for high-performance or mission-critical applications because its simplicity comes at the cost of durability, scalability, and advanced query performance.

```bash
CREATE TABLE external_contacts (
    id INT,
    name VARCHAR(100),
    email VARCHAR(150)
) ENGINE=CSV;

INSERT INTO external_contacts
VALUES (1, 'Alex', 'alex@example.com');

SELECT * FROM external_contacts;
```

## MRG_MyISAM

- MRG_MyISAM, also called the MERGE engine, combines multiple compatible MyISAM tables into one logical table. The underlying tables must have compatible structures.
- Imagine having monthly tables:

- sales_january
- sales_february
- sales_march.

- A MERGE table can expose their rows through one logical table. Example

```bash
CREATE TABLE sales_january (
    id INT,
    amount DECIMAL(10,2)
) ENGINE=MyISAM;

CREATE TABLE sales_february (
    id INT,
    amount DECIMAL(10,2)
) ENGINE=MyISAM;

CREATE TABLE all_sales (
    id INT,
    amount DECIMAL(10,2)
) ENGINE=MRG_MyISAM
UNION=(sales_january,sales_february)
INSERT_METHOD=LAST;

then 

SELECT * FROM all_sales;
```

- Important: MERGE does not make the underlying tables transactional or turn them into one physically unified table.
- It is a specialized compatibility mechanism, not a replacement for partitioning or modern analytical architecture.

## SEQUENCE

- SEQUENCE is a virtual table engine that generates sequential numeric values.
- It is useful for producing number ranges without first creating a physical table of numbers. Example

```bash
SELECT *
FROM seq_1_to_10;

SELECT *
FROM seq_100_to_110;
```

## Common use cases

- The engine is particularly useful when SQL needs generated rows without creating helper tables. Typical applications include:
- generating integer ranges
- filling gaps in reports
- producing calendar or date series
- expanding result sets for joins
- testing queries with synthetic data
- mathematical or analytical SQL problems such as prime-number generation

```bash
SELECT seq AS test_id
FROM seq_1_to_100;
```

- Galera note: This engine generates values rather than maintaining ordinary application records. Use it as a query utility, not as your primary table engine.

## PERFORMANCE_SCHEMA

- PERFORMANCE_SCHEMA is a built-in MariaDB subsystem that provides structured instrumentation for observing how the database server operates internally.
- This is a special engine associated with the Performance Schema. It exposes instrumentation and diagnostic data about server activity, rather than storing normal application records.
- Rather than storing application data, it exposes detailed runtime information about server activity, helping administrators and developers analyze performance, diagnose bottlenecks, and better understand workload behavior.

```bash
SELECT *
FROM performance_schema.threads
LIMIT 10;

SELECT *
FROM performance_schema.setup_instruments
LIMIT 10;
```

- When to use it: Monitoring query execution, threads, waits and server activity.

## Creating your own Database, and Manipulating it

- We'll use your MariaDB Galera lab and InnoDB as the storage engine, so you can practice creating databases, designing tables, inserting records, modifying data, and eventually managing changes across all three nodes.

```bash
Create Database training;
CREATE DATABASE IF NOT EXISTS Training;       | Would create it if it does not Exists.
CREATE DATABASE Training;                     | Would create a database. 

SHOW DATABASES LIKE 'Train%';                 | Would show databases of same pattern
Select Database();                            | Returns currently selected database or Null if none is selected. 
USE training;                                 | Used to select the database to work with
DROP DATABASE Training;                       | Deletes the database and all its objects and data.

CREATE DATABASE Training
CHARACTER SET utf8mb4                         | CHARACTER SET utf8mb4: supports Unicode text, including many international characters and emoji.
COLLATE utf8mb4_unicode_ci;                   | COLLATE utf8mb4_unicode_ci: determines how strings are compared and sorted; ci means case-insensitive.
```

- What it does: Creates a new database named Training on the MariaDB server.
- A database is a logical container for objects such as tables, views, stored procedures, triggers and events. Creating the database does not automatically create any tables or insert data.
- DROP DATABASE permanently removes the database's tables and their contents. In your Galera cluster, this change can propagate to the other nodes.

## Create your first table

```bash
 CREATE TABLE `employees` (
  `employee_id` int(11) NOT NULL AUTO_INCREMENT,
  `first_name` varchar(50) NOT NULL,
  `last_name` varchar(50) NOT NULL,
  `department` varchar(50) DEFAULT NULL,
  `salary` decimal(10,2) DEFAULT NULL,
  `hire_date` date DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`employee_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci;

INSERT INTO employees
(first_name, last_name, department, salary, hire_date, phone)
VALUES
('Bill', 'John', 'IT', 83000, '2023-06-10', '4077776571'),
('Pamela', 'Jones', 'Finance', 93000, '2022-03-20', '4077776572'),
('Sandra', 'Angela', 'Finance', 98000, '2025-02-01', '4077776573'),
('Fechi', 'Greg', 'Finance', 93000, '2022-03-20', '4077776575'),
('Nelson', 'Iben', 'Admin', 98000, '2025-02-01', '4077776576'),
('Serena', 'Biya', 'Admin', 79000, '2024-01-15', '4077776578'),
('Dike', 'John', 'Warehouse', 83000, '2023-06-10', '4077776579');

SELECT * FROM order_items 
WHERE order_id = 6 AND (unit_price * quantity) > 30;

CREATE TABLE products (
    product_id INT,
    name VARCHAR(50),
    quantity_in_stock INT NOT NULL,
    status VARCHAR(60),
    unit_price DECIMAL
) ENGINE=InnoDB;                              | To create table called employees.

INSERT INTO products
(product_id, name, quantity_in_stock, status, unit_price)
VALUES
('2', 'Metallic plate', '4', 'completed', '2.00'),
('2', 'Metallic plate', '4', 'inprogress', '2.00'),
('2', 'Metallic plate', '4', 'started', '2.00'),
('3', 'Rubber plate', '20', 'completed', '4.05'),
('3', 'Rubber plate', '20', 'completed', '4.05'),
('3', 'Rubber plate', '20', 'started', '4.05'),
('4', 'Wooden plate', '21', 'completed', '5.00'),
('4', 'Wooden plate', '21', 'started', '5.00'),
('4', 'Wooden plate', '21', 'started', '5.00'),
('4', 'Wooden plate', '21', 'completed', '5.00'),
('5', 'Golden plate', '22', 'completed', '10.00'),
('5', 'Golden plate', '22', 'started', '10.00'),
('6', 'Silver plate', '28', 'completed', '9.00'),
('6', 'Silver plate', '28', 'started', '9.00'),
('7', 'Bronze plate', '29', 'completed', '8.00'),
('7', 'Bronze plate', '29', 'completed', '8.00'),
('7', 'Bronze plate', '29', 'inprogress', '8.00');

CREATE TABLE customers (
    customer_id INT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    city VARCHAR(50) NOT NULL,
    state VARCHAR(50) NOT NULL,
    address VARCHAR(50) NOT NULL,
    phone VARCHAR(20) DEFAULT NULL,
    birth_date DATE,
    points INT
) ENGINE=InnoDB; 

INSERT INTO customers
(customer_id, first_name, last_name, city, state, address, phone, birth_date, points)
VALUES
('1', 'Emeka', 'Umejiofor', 'Manchester', 'UK', '1042 manchester way', '4077776564','1992-09-04', '2244'),
('2', 'Ola', 'Paul', 'Manchester', 'UK', '1043 osborne way', '4097776564','1975-09-04', '2144'),
('3', 'Abraham', 'Enessi', 'Colchester', 'UK', '1042 colchester way', '4078776564','1990-09-04', '2234'),
('4', 'Fechi', 'Greg', 'Liverpool', 'UK', '1042 liverpool way', '4077776364','1989-09-04', '2254'),
('5', 'Obats', 'Samuel', 'Ojota', 'Lagos', '1045 gordons way', '4077776564','1987-09-04', '2044'),
('6', 'George', 'Umej', 'Idimu', 'Oyo', '1042 manchester way', '4077756564','1985-09-04', '2284'),
('7', 'Uzor', 'Umeji', 'Oluyole', 'Ibadan', '1042 oluyole way', '4077775564','1986-09-04', '2249'),
('8', 'Bola', 'Tolani', 'Oshodi', 'Lagos', '1042 ewenla way', '4077746564','1985-09-04', '1244'),
('9', 'Bolanle', 'Wunmi', 'Makoko', 'Kwara', '1048 makoko way', '4073776564','1991-09-04', '3244'),
('10', 'Franklin', 'Anoyinka', 'Isolo', 'Anambra', '0042 junction way', '4177776564','1994-09-04', '4244'),
('11', 'Olaide', 'Olubi', 'Isolo', 'Lagos', '1042 idimu way', '4077776364','1992-09-04', '5244');

USE Training;

CREATE TABLE Students (
    student_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(150) UNIQUE,
    enrollment_date DATE,
    status VARCHAR(20) DEFAULT 'Active'
) ENGINE=InnoDB;                              | To create table called Students.

Definition                                      Purpose

employee_id INT                                 Integer Identifier
AUTO_INCREMENT                                  Automatically generates the next ID
PRIMARY KEY                                     Uniquely identifies each row
VARCHAR(50)                                     Variable-length text up to 50 characters
NOT NULL                                        Requires a value
UNIQUE                                          Prevents duplicate non-NULL email values
DATE                                            Stores a calendar date
DEFAULT 'Active'                                Uses Active when no status is supplied
ENGINE=InnoDB                                   Selects the storage engine
```

Practice statements:

Topic                                       Sample command
Read                                        SELECT *FROM employees;
Filter                                      SELECT * FROM employees WHERE department='IT';
Sort                                        SELECT * FROM employees ORDER BY salary DESC;
Limit                                       SELECT * FROM employees LIMIT 2;
Update                                      UPDATE employees SET salary=78000 WHERE employee_id=1;
Delete                                      DELETE FROM employees WHERE employee_id=4;
Count                                       SELECT COUNT(*) FROM employees;
Group                                       SELECT department, AVG(salary) FROM employees GROUP BY department;

- You'll see the field names, types, whether NULL is allowed, key information, defaults and extra properties.

```bash
Describe table_name;                             | Would describe the table showing fields, type, Null, key, default and extra sections. 
Desc table_name;                                 | Shorthand format. 

SHOW CREATE TABLE Students;                 | Outputs how the table students was created. 

MariaDB [training]> SHOW CREATE TABLE Students;
+----------
| Table    | Create Table                                                                                                                                                                                                                                                                                                                                                                                         
| Students | CREATE TABLE `students` (
  `student_id` int(11) NOT NULL AUTO_INCREMENT,
  `first_name` varchar(50) NOT NULL,
  `last_name` varchar(50) NOT NULL,
  `email` varchar(150) DEFAULT NULL,
  `enrollment_date` date DEFAULT NULL,
  `status` varchar(20) DEFAULT 'Active',
  PRIMARY KEY (`student_id`),
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3 COLLATE=utf8mb3_unicode_ci |
------------+
1 row in set (0.001 sec)
```

## Alter Tables

```bash
ALTER TABLE Students
ADD phone VARCHAR(20);                                           | Would alter table to add phone column with a 20 xter var. 

ALTER TABLE employees
MODIFY phone VARCHAR(30);                                        | Would modify the VARCHAR section to 30.

ALTER TABLE Students
CHANGE phone phone_number VARCHAR(30);                           | Would alter or change the name of a column.

ALTER TABLE Students
DROP COLUMN phone_number;                                        | Would drop / delete a column from the table.

RENAME TABLE Students TO Learners;                               | Would rename a table to a new name.
```

- Important: ALTER TABLE can require a table rebuild or substantial work, depending on the operation and MariaDB version. For production-sized tables, consider the impact before changing a schema.

## Drop Table

```bash
DROP TABLE Students;                                              | Would delete a table and its data/structures.
DROP TABLE IF EXISTS Students;

TRUNCATE TABLE Students;                                          | Deletes all records while keeping the table definition.

- TRUNCATE is a DDL operation and generally resets the AUTO_INCREMENT counter. It cannot be used as an ordinary transactional rollback operation.
```

## Inserting, reading, updating and deleting data (DML)

- DML stands for Data Manipulation Language. These are the commands you'll use constantly when working with application data.

## Insert - Add records

```bash
INSERT INTO Students
    (first_name, last_name, email, enrollment_date)
VALUES
    ('Paul', 'Umej', 'paul@example.com', '2026-09-28');                                 | Would insert a single student record.


INSERT INTO Students
    (first_name, last_name, email, enrollment_date)
VALUES
    ('Alex', 'Brown', 'alex@example.com', '2026-09-28'),
    ('Mary', 'Smith', 'mary@example.com', '2026-09-29'),
    ('John', 'Davis', 'john@example.com', '2026-09-30');                                | Would insert multiple student records.

INSERT INTO students
(first_name, last_name, email, enrollment_date, status, phone)
VALUES
('Paul', 'Saul', 'paul@gmail.com', '2024-01-15', 'active', '9043213456'),
('Mark', 'Okeke', 'mark@gmail.com', '2023-06-10' 'active', '9043213459'),
('Peteru', 'Bob', 'peter@gmail.com', '2022-03-20', 'active', '9043213446'),
('Emekus', 'Browning', 'peter1@gmail.com', '2023-03-20', 'active', '9043213458'),
('Sandra', 'Umejiofor', 'sandra@yahoo.com', '2025-02-01', 'inactive', '9043213476');                 | Would insert data to the table. 

SELECT * FROM Students;                                                                 | Retrieve all columns and rows: Would return all contents of Table.

- Retrieve selected columns

SELECT first_name, last_name, email
FROM Students;                                                                          | Retrieve selected columns:

- Filter records with Where

SELECT *
FROM Students
WHERE status = 'Active';                                                                | Would filter students table for status active.

- Filter using multiple conditions

SELECT *
FROM Students
WHERE status = 'Active'
AND enrollment_date >= '2026-09-01';                                                    | Would return records with date greater than 01/09/2026.

SELECT *
FROM Students
ORDER BY last_name ASC;                                                                 | Would sort the output in Ascending order. 

SELECT *
FROM Students
WHERE first_name LIKE 'Ma%';                                                            | Would sort a specific item from the table. Using a partial string.

ASC means ascending; DESC means descending.
% matches any sequence of characters. _ matches one character.
```

## Update - modify existing records in a table

```bash
UPDATE Students
SET status = 'Completed'
WHERE student_id = 1;                                                                   | Would update status field to completed for where student_id = 1.

- Updating more than one columns

UPDATE Students
SET
    first_name = 'Deco',
    enrollment_date = '2026-09-28'
WHERE student_id = 1;                                                                   | Would update the 2 columns.

or

update students SET first_name = 'Fechi', last_name = 'Greg', enrollment_date
= '2026-09-27', phone = '3213181175' WHERE student_id = 3;

- Updating multiple rows with matching fields

UPDATE Students
SET status = 'Inactive'
WHERE enrollment_date < '2026-09-01';                                                   | Would update columns with matching field where enrollment date is less than specified date.

UPDATE Students
SET status = 'Inactive';                                                                | This changes every row in the table because there is no WHERE clause.

- The most important UPDATE rule. Always check your WHERE clause before executing an update.
```

## Deleting - Remove selected records

```bash
DELETE FROM Students
WHERE student_id = 3;                                                                   | Would delete a student record where student_id is 3.

DELETE FROM Students
WHERE status = 'Inactive';                                                              | Would delete all records matching the where condition. 

DELETE FROM Students;                                                                   | Would delete every record but preserve the table.

- Unlike TRUNCATE, DELETE is a DML statement and can be rolled back when executed inside an active transaction and not yet committed.
```

## REPLACE and INSERT ... ON DUPLICATE KEY UPDATE

- REPLACE inserts a row, but if a primary or unique key conflicts, it effectively deletes the conflicting row and inserts the new one.
- This can have consequences for foreign keys, triggers and auto-increment values.

```bash
REPLACE INTO Students
    (student_id, first_name, last_name, email)
VALUES
    (1, 'Paul', 'Umej', 'paul@example.com');                                            | This would insert a single row to the table.


INSERT INTO Students
    (student_id, first_name, last_name, email)
VALUES
    (1, 'Paul', 'Umej', 'paul@example.com')
ON DUPLICATE KEY UPDATE
    email = VALUES(email);                                                        | This updates the existing row when a duplicate key is encountered, rather than replacing the whole row.
```

## Database constraints and indexes

- Constraints help maintain data integrity.
- Indexes help MariaDB find records efficiently.

## Common constraints

Constraint                              Purpose

PRIMARY KEY                             Unique row identifier
FOREIGN KEY                             Enforces a relationship to another table
UNIQUE                                  Prevents duplicate values
NOT NULL                                Requires a value
CHECK                                   Enforces a condition on values
DEFAULT                                 Supplies a value when one is omitted

- Example use of foreign key and references between 2 tables

```bash
CREATE TABLE Courses (
    course_id INT AUTO_INCREMENT PRIMARY KEY,
    course_name VARCHAR(100) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE Enrollments (
    enrollment_id INT AUTO_INCREMENT PRIMARY KEY,
    student_id INT NOT NULL,
    course_id INT NOT NULL,
    enrollment_date DATE NOT NULL,
    FOREIGN KEY (student_id)
        REFERENCES Students(student_id),
    FOREIGN KEY (course_id)
        REFERENCES Courses(course_id)
) ENGINE=InnoDB;

- This add a Courses table and links it to Students through a registration table.
- The foreign keys prevent an enrollment from referring to a nonexistent student or course.
```

## Create index - used to speed up certain searches and joins

```bash
CREATE INDEX idx_students_last_name
ON Students(last_name);                                                             | Would create index idx_students_last_name on students table.

CREATE INDEX idx_email ON Students(email);                                          | Would create index idx_email on students table.

show index from students;                                                           | Would return all indexes available on table.

DROP INDEX idx_students_last_name ON Students;                                      | Used to drop an index.
```

- For a table with a large number of records, indexing columns used frequently in filtering, sorting and joins can improve query performance.
- However, unnecessary indexes consume storage and slow down writes.

## Transaction commands (TCL)

- TCL stands for Transaction Control Language. Transactions let you treat multiple changes as one logical unit. The main commands are:

Command                                             Purpose

START TRANSACTION                                   Begins a transaction
COMMIT                                              Makes its changes permanent
ROLLBACK                                            Undoes uncommitted changes
SAVEPOINT                                           Marks a point inside a transaction
ROLLBACK TO SAVEPOINT                               Undoes changes made after a savepoint

Example

```bash
START TRANSACTION;

UPDATE Students
SET status = 'Active'
WHERE student_id = 1;

SAVEPOINT after_student;

UPDATE Students
SET status = 'Inactive'
WHERE student_id = 3;

ROLLBACK TO SAVEPOINT after_student;

COMMIT;

or

start transaction; update students SET status = 'Active' WHERE student_id = 1; savepoint after_student; update students set status = 'Inactive' where student_id =3; rollback to savepoint after_student; commit;

- Here, the change to student 1 is committed. The change to student 2 is rolled back.
```

## User and privilege commands (DCL)

- DCL stands for Data Control Language. These commands manage who can access your database and what they can do. To create a user

```bash
CREATE USER 'Emeka'@'%'
IDENTIFIED BY 'Use-A-Strong-Password';

- Grant permissions on your Training database:

GRANT SELECT, INSERT, UPDATE, DELETE
ON Training.*
TO 'Emeka'@'%';

- Inspect the user's permissions:

SHOW GRANTS FOR 'Emeka'@'%';                                                  | Inspect user's permissions

- Revoke permissions

REVOKE DELETE
ON Training.*
FROM 'Emeka'@'%';                                                              | Revoke and delete permissions

DROP USER 'Emeka'@'%';                                                         | Drop user Emeka

- The % host wildcard allows matching connections from different hosts, subject to MariaDB's account matching rules and network security.
```

In Summary

Database Management

CREATE DATABASE                   Create a database
SHOW DATABASES                    List databases
USE                               Select the active database
ALTER DATABASE                    Change database defaults
DROP DATABASE                     Remove a database

Table Management

CREATE TABLE                      Create a Table
SHOW TABLES                       List Tables
DESCRIBE / DESC                   Inspect columns
SHOW CREATE TABLE                 Inspect full table definition
ALTER TABLE                       Modify a table
RENAME TABLE                      Rename a table
TRUNCATE TABLE                    Remove all rows and retain structure
DROP TABLE                        Remove a table

Data Manipulation

INSERT                                  Add records
SELECT                                  READ records
UPDATE                                  Modify records
DELETE                                  Remove records
REPLACE                                 Replace a conflicting row
INSERT ... ON DUPLICATE KEY UPDATE      Insert or update

Integrity and Performance

PRIMARY KEY / FOREIGN KEY               Define row identity and relationships
UNIQUE / CHECK                          Enforce data rules
CREATE INDEX
SHOW INDEX                              Inspect indexes
DROP INDEX                              Remove an index

Transaction and Access

START TRANSACTION                       Begin a transaction
COMMIT                                  Save changes
ROLLBACK                                Undo uncommitted changes
SAVEPOINT                               Mark a rollback point
CREATE USER                             Create an account
GRANT / REVOKE                          Manage permissions
SHOW GRANTS                             Inspect permissions

## IN / NOT IN operator

- The IN operator allows you to test whether a column matches one of several specified values

```bash
SELECT *
FROM employees
WHERE department IN ('IT', 'HR', 'admin', 'warehouse', 'storeroom');

vs using 

SELECT *
FROM employees
WHERE department = 'IT'
   OR department = 'HR';

SELECT *
FROM employees
WHERE department NOT IN ('IT', 'HR');                               | Would do the opposite of IN operator. 
```

- IN is cleaner when you have multiple possible values. The NOT IN operator does the opposite of the IN operator.

## BETWEEN Operator

- BETWEEN checks whether a value falls within a specified range. Example

```bash
WHERE column BETWEEN lower_value AND upper_value

SELECT first_name, last_name, salary
FROM employees
WHERE salary BETWEEN 60000 AND 90000;

SELECT first_name, last_name, hire_date
FROM employees
WHERE hire_date BETWEEN '2022-01-01' AND '2024-12-31';
```

## NOT BETWEEN

- This does the opposite of the between operator. Example

```bash
SELECT first_name, last_name, salary
FROM employees
WHERE salary NOT BETWEEN 60000 AND 90000;                                       | This returns employees whose salary is outside that range.
```

## Order By

- ORDER BY sorts the results of your query either by ascending or descending order or by a different set of order. Example

```bash
SELECT *
FROM employees
ORDER BY column;                            | Default is ASCENDING ORDER

SELECT first_name, last_name, salary
FROM employees
ORDER BY salary ASC;                                                        | Sort in ascending order

SELECT first_name, last_name, department
FROM employees
ORDER BY last_name ASC;                                                     | Would sort alphabetically

SELECT first_name, last_name, department, salary
FROM employees
ORDER BY department ASC, salary DESC;                                       | Sort by multiple columns.
```

## AND / OR

- These operators allow you to combine multiple conditions. AND means all conditions must be true. Example

```bash
SELECT first_name, last_name, department, salary
FROM employees
WHERE department = 'IT'
AND salary > 70000;                                                         | Find IT employees earning more than $70,000: An employee must satisfy both conditions.

OR means at least one condition must be true. Example Find employees who are either in IT or HR:

SELECT first_name, last_name, department, salary
FROM employees
WHERE department = 'IT' OR department = 'storeroom' OR department = 'finance'
ORDER BY salary ASC;                                                        | Would output data from each departments
```

## Combining AND and OR

```bash
SELECT first_name, last_name, department, salary
FROM employees
WHERE (department = 'IT' OR department = 'STOREROOM')
AND salary > 70000;                                                         | Would output both conditions
```

When mixing AND and OR, use parentheses even when you think they're unnecessary.

## NOT Operator also represented as <>

- NOT reverses a condition. Example

```bash
SELECT first_name, last_name, department
FROM employees
WHERE NOT department = 'IT';                                                | Would output department list except IT department

SELECT first_name, last_name, department
FROM employees
WHERE department <> 'IT';

SELECT first_name, last_name, department
FROM employees
WHERE department NOT IN ('IT', 'storeroom');                                       | Used with IN to give same output

SELECT first_name, last_name, salary
FROM employees
WHERE salary NOT BETWEEN 60000 AND 90000;                                          | Used with BETWEEN / AND operators

SELECT first_name, last_name
FROM employees
WHERE first_name NOT LIKE 'A%';                                                    | Used with NOT LIKE
```

## LIMIT CLAUSE operator

- LIMIT controls how many rows MariaDB returns. Example

```bash
SELECT *
FROM employees
LIMIT 5;                                                                           | Would return first 5 rows

LIMIT with ORDER BY

SELECT first_name, last_name, salary
FROM employees
ORDER BY salary DESC
LIMIT 3;    

Limit with an Offset

SELECT *
FROM employees
LIMIT 5, 10;                                                                       | Skip the first 5 rows and return the next 10.

SELECT columns
FROM table
WHERE row_conditions
GROUP BY grouping
HAVING group_conditions
ORDER BY sorting
LIMIT number_of_rows;                                                              | Standard sql query format.
```

## Summary

| Operator / Clause    | Purpose                     | Example                              |
| -------------------- | --------------------------- | ------------------------------------ |
| `IN`                 | Match one of several values | `department IN ('IT','HR')`          |
| `NOT IN`             | Exclude several values      | `department NOT IN ('IT','HR')`      |
| `BETWEEN`            | Match a range               | `salary BETWEEN 60000 AND 90000`     |
| `NOT BETWEEN`        | Exclude a range             | `salary NOT BETWEEN 60000 AND 90000` |
| `ORDER BY`           | Sort results                | `ORDER BY salary DESC`               |
| `AND`                | All conditions must be true | `dept='IT' AND salary>70000`         |
| `OR`                 | At least one condition true | `dept='IT' OR dept='HR'`             |
| `NOT`                | Reverse a condition         | `NOT department='IT'`                |
| `LIMIT`              | Restrict number of rows     | `LIMIT 5`                            |
| `LIMIT offset,count` | Pagination                  | `LIMIT 10,10`                        |

## JOIN operator

- The join operator is used for selecting/refrencing data from 2 or more tables. Example, there must be a unique column that matches both tables.

```bash
INNER JOIN

select order_id, orders.customer_id, first_name, last_name from customers 
JOIN orders ON orders.customer_id = customers.customer_id;                        | This would select the columns from both specified tables. o and c Are used as Alias for the tables.

select oi.order_id, p.name, oi.product_id, quantity, oi.unit_price from products p 
JOIN order_items oi ON p.product_id = oi.product_id;                                    | Returns data from both tables. 

- When you use the join operator with an alias, you must complete your expression using the alias. 
```

## Joining accross Databases

- The join operator is used for selecting/refrencing data from 2 or more tables and databases.
- You only have to prefix the table missing in current database with the database name. Example

```bash
select * from products p
JOIN db_store.order_items oi ON oi.product_id = p.product_id limit 3;                    | Would output data from db_store and products table in db_inventory. 

select p.product_id, name, p.quantity_in_stock, p.unit_price, oi.quantity, oi.unit_price from products p JOIN db_store.order_items oi ON oi.product_id = p.product_id limit 3;

select * from db_store.order_items oi
JOIN products p ON oi.product_id = p.product_id;                                         | Would output same data from 2 dbs.
```

## Slef Joins

- Enables you to run queries using join command on a single table. The join command combines 2 columns in the table. Example

```bash
select * from employees e
JOIN employees m ON e.reports_to = m.employee_id limit 5;                               | The alias must be unique for the tables. 

select e.employee_id, e.first_name, m.last_name as manager_name from employees e 
JOIN employees m ON e.reports_to = m.employee_id limit 5;                               | Using self join with Unique alias.
```

## Joining multiple tables

- You can use the JOIN command to join multiple tables also, Example

```bash
select * from orders o 
JOIN customers c ON o.customer_id = c.customer_id 
JOIN order_statuses os ON os.order_status_id = o.status limit 3;                        | Using join command on multiple tables. Would return the 3 tables.


select o.order_id, o.order_date, c.first_name, c.last_name, os.name as status from orders o 
JOIN customers c ON o.customer_id = c.customer_id 
JOIN order_statuses os ON os.order_status_id = o.status limit 3;                                    | Using join comands on multiple tables. 

- Write a query and join the payments table with payment_methods table as well as clients table. Produce a report that shows payments with more details such as the name of the client and the payment method. Solution

select p.invoice_id, c.name, c.address, c.phone, pm.name as payment_method, p.date, p.amount from clients c 
JOIN payments p ON p.client_id = c.client_id 
JOIN payment_methods pm ON p.payment_method = pm.payment_method_id;
```

## Compound JOIN commands

- Used for combining multiple columns where a single column cannot be used to uniquely identify a row. The table would normally have a composite primary key. Present in 2 columns. Example

```bash
select * from order_items oi
JOIN order_item_notes oin ON oi.order_id = oin.order_id AND oi.product_id = oin.product_id;                 | Example of a compound join statement.
```

## Outer JOIN commands

- These are opposite of INNER join commands, used to return either the left or right side data from a table. Example

```bash
select o.order_id, o.order_date, c.first_name, c.last_name from orders o 
RIGHT JOIN customers c ON o.customer_id = c.customer_id
ORDER BY c.customer_id;                                                                                        | Would return data from the customers table.

Write a query to join the order_items table with the products table so we can see how many times each product is ordered. Return both left and right join queries. 

select p.product_id, oi.order_id, p.name, p.quantity_in_stock, oi.unit_price from products p
LEFT JOIN order_items oi ON p.product_id = oi.product_id                                                       | Would return both tables using the left join.

select o.order_date, o.order_id, c.first_name, sh.name as Shipper, os.name as status from orders o
JOIN customers c ON o.customer_id = c.customer_id
Left JOIN shippers sh ON sh.shipper_id = o.shipper_id
JOIN order_statuses os ON os.order_status_id = o.status;                                                       | Left outer join and Inner join command use.

- Write a query that this table output: order_date, order_id, first_name, shipper and status.

select o.order_date, o.order_id, c.first_name, sh.name as Shipper, os.name as status from orders o
JOIN customers c ON o.customer_id = c.customer_id
Left JOIN shippers sh ON sh.shipper_id = o.shipper_id
JOIN order_statuses os ON os.order_status_id = o.status;

- Write a query to select a payments from payments table and produce table with date, client, amount and name *payment method name'.
use db_invoicing
select p.date, c.name as client, p.amount, pm.name as payment_method_name from payments p
left JOIN payment_methods pm ON pm.payment_method_id = p.payment_method
left JOIN clients c ON c.client_id = p.client_id;
left JOIN clients c USING (client_id);                                                       | The USING clause, can be used in place of the JOIN command when the columns are similar.

- Write a query to produce report customer_id, first_name, points, type. If points is < 2000, they have bronze, if btw 2000 to 3000 points they are silver and if the points is > 3000 they are gold customers. Sort the result by the first name.

select customer_id, first_name, points, 'Bronze' AS type FROM customers
where points < 2000
UNION
select customer_id, first_name, points, 'Silver' AS type FROM customers
where points between 2000 and 3000
UNION
select customer_id, first_name, points, 'Gold' AS type FROM customers
where points > 3000
order by first_name;                                                                                | Shows the use of union as joining strategy.
```

## Renaming a DATABASE

- Yes, but MariaDB does not have a simple RENAME DATABASE command.
- For a database with tables, the usual approach is:

Create the new database.

```bash
CREATE DATABASE mysql_training;
```

- Move/rename the tables into it.

```bash
RENAME TABLE training.employees
TO mysql_training.employees;

RENAME TABLE training.employees
TO mysql_training.employees;

RENAME TABLE training.departments
TO mysql_training.departments;

RENAME TABLE training.order_items
TO mysql_training.order_items;
```

- Verify everything.

```bash
SHOW DATABASES;

USE mysql_training;
SHOW TABLES;
```

- Drop the old database once you're sure.

## Module 3 — Database Design, Constraints and Indexes

1. Primary Keys

- A primary key (PK) uniquely identifies every row in a table. For example, your employees table probably has: during creation

```bash
employee_id INT AUTO_INCREMENT PRIMARY KEY

SHOW INDEX FROM employees;                                          | Used to show primary key of a table.
```

- This means:

- employee_id must be unique.
- It cannot be NULL.
- MariaDB can use it to identify a specific employee.
- AUTO_INCREMENT generates IDs automatically.

1. Foreign keys

- A foreign key (FK) establishes a relationship between two tables. References the departments table.

```bash
CREATE TABLE employees (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    department_id INT,

    FOREIGN KEY (department_id)
        REFERENCES departments(department_id)
);
```

1. UNIQUE Constraint

- UNIQUE prevents duplicate values. When creating a table you can use the UNIQUE feature against the specified column. Example

```bash
CREATE TABLE employee_contacts (
    employee_id INT PRIMARY KEY,
    email VARCHAR(150) UNIQUE                                                           | Here email column would be marked Unique and would not accept duplicates.
);


ALTER TABLE employees
ADD CONSTRAINT uk_employee_phone UNIQUE (phone);                                        | Creats a Unique constraint after creating a table.
```

1. NOT NULL

- NOT NULL means the column must have a value. Example

```bash
CREATE TABLE employees2 (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    salary DECIMAL(10,2)                                                               | Example use of NOT NULL. first_name and last_name columns must have values.
);
```

1. CHECK Constraint

- CHECK prevents values that don't make sense.
- A constraint protects the database regardless of which application is inserting the data. Example

```bash
CREATE TABLE employees3 (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    salary DECIMAL(10,2),

    CHECK (salary >= 0)                                                                | Would check that salary column value is >= 0.
);

You can use more complex checks. Examples 

CHECK (salary >= 15000 AND salary <= 1000000)
CHECK (department IN ('IT', 'HR', 'Finance', 'Sales'))
```

1. DEFAULT VALUE

- A default value is automatically supplied when you don't provide one. Example

```bash
CREATE TABLE employees4 (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    status VARCHAR(20) DEFAULT 'Active'                                                         | Example use of DEFAULT value. 
);
```

## In summary - Putting the Constraints Together. Here's a more realistic employees table

```bash
CREATE TABLE employees (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,

    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,

    email VARCHAR(150) NOT NULL UNIQUE,

    salary DECIMAL(10,2) NOT NULL
        CHECK (salary >= 0),

    status VARCHAR(20) NOT NULL
        DEFAULT 'Active',

    hire_date DATE NOT NULL,

    created_at TIMESTAMP
        DEFAULT CURRENT_TIMESTAMP
);
```

## One-to-One Relationship

- One record in Table A corresponds to at most one record in Table B. Example

```bash
CREATE TABLE employees (
    employee_id INT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL
);

CREATE TABLE employee_details (
    employee_id INT PRIMARY KEY,

    address VARCHAR(200),
    emergency_contact VARCHAR(100),

    FOREIGN KEY (employee_id)
        REFERENCES employees(employee_id)
);
```

## One-to-Many Relationship

- One department has many employees:
- In a one-to-many relationship, the foreign key normally belongs in the "many" table. Example

Department
    |
    +---- Employee
    |
    +---- Employee
    |
    +---- Employee

```bash
CREATE TABLE departments (
    department_id INT AUTO_INCREMENT PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE employees (
    employee_id INT AUTO_INCREMENT PRIMARY KEY,
    first_name VARCHAR(50) NOT NULL,
    department_id INT NOT NULL,

    FOREIGN KEY (department_id)
        REFERENCES departments(department_id)
);
```

## Data Types

- Integer data types includes
    TINYINT
    SMALLINT
    MEDIUMINT
    INT
    BIGINT

- Decimal data type

    DECIMAL(10,2) means 10 digits and 2 digits after decimal

- Character / String datatypes
    CHAR - Fixed length string
    VARCHAR - Variable length string
    TEXT - for larger pieces of text

- Date and Time data types
    DATE
    TIME
    DATETIME
    TIMESTAMP
    YEAR

- Binary datatype
    BINARY
    VARBINARY
    BLOB
    MEDIUMBLOB
    LONGBLOB

## Indexes

- An index is a data structure that helps MariaDB find rows more efficiently. Example

```bash
CREATE INDEX idx_employees_last_name
ON employees(last_name);                                        | Would create an index for the database.

SHOW INDEX FROM employees;                                      | Used to show indexes on a table.
```

## Join accross Databases
