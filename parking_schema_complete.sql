-- ============================================================
--   University Parking Permit System — Complete Database Schema
--   Student: Azhan Masood  |  SAP ID: 62914
--   Instructor: Mr. Ithisham Ullah  |  Subject: Database Systems
--   Semester: 4th  |  April 2026
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- SECTION 1: CREATE TABLES (Core Schema Objects)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE Users (
    user_id    INT           NOT NULL AUTO_INCREMENT,
    name       VARCHAR(100)  NOT NULL,
    role       VARCHAR(50)   NOT NULL,
    department VARCHAR(100),
    phone      VARCHAR(20),
    CONSTRAINT PK_Users PRIMARY KEY (user_id),
    CONSTRAINT CHK_Role CHECK (role IN ('Student', 'Teacher', 'Admin'))
);

CREATE TABLE Vehicle (
    vehicle_id     INT          NOT NULL AUTO_INCREMENT,
    vehicle_number VARCHAR(20)  NOT NULL,
    vehicle_type   VARCHAR(50)  NOT NULL,
    user_id        INT          NOT NULL,
    CONSTRAINT PK_Vehicle       PRIMARY KEY (vehicle_id),
    CONSTRAINT UQ_VehicleNumber UNIQUE (vehicle_number),
    CONSTRAINT FK_Vehicle_User
        FOREIGN KEY (user_id) REFERENCES Users(user_id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE ParkingZone (
    zone_id   INT         NOT NULL AUTO_INCREMENT,
    zone_name VARCHAR(50) NOT NULL,
    capacity  INT         NOT NULL DEFAULT 0,
    CONSTRAINT PK_ParkingZone PRIMARY KEY (zone_id),
    CONSTRAINT CHK_Capacity CHECK (capacity >= 0)
);

CREATE TABLE Permit (
    permit_id   INT  NOT NULL AUTO_INCREMENT,
    vehicle_id  INT  NOT NULL,
    zone_id     INT  NOT NULL,
    issue_date  DATE NOT NULL,
    expiry_date DATE NOT NULL,
    CONSTRAINT PK_Permit        PRIMARY KEY (permit_id),
    CONSTRAINT UQ_VehiclePermit UNIQUE (vehicle_id),
    CONSTRAINT FK_Permit_Vehicle
        FOREIGN KEY (vehicle_id) REFERENCES Vehicle(vehicle_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT FK_Permit_Zone
        FOREIGN KEY (zone_id) REFERENCES ParkingZone(zone_id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT CHK_Dates CHECK (expiry_date > issue_date)
);

-- ─────────────────────────────────────────────────────────────
-- SECTION 2: INDEXES
-- ─────────────────────────────────────────────────────────────

-- Speed up lookups by user role
CREATE INDEX IDX_Users_Role ON Users(role);

-- Speed up vehicle lookups by owner
CREATE INDEX IDX_Vehicle_UserID ON Vehicle(user_id);

-- Speed up permit expiry queries (most common query)
CREATE INDEX IDX_Permit_Expiry ON Permit(expiry_date);

-- Speed up zone-based permit queries
CREATE INDEX IDX_Permit_Zone ON Permit(zone_id);

-- ─────────────────────────────────────────────────────────────
-- SECTION 3: VIEWS
-- ─────────────────────────────────────────────────────────────

-- View 1: Active permits with full details
CREATE VIEW vw_ActivePermits AS
SELECT
    p.permit_id,
    u.name          AS user_name,
    u.role          AS user_role,
    u.department,
    v.vehicle_number,
    v.vehicle_type,
    z.zone_name,
    p.issue_date,
    p.expiry_date,
    DATEDIFF(p.expiry_date, CURRENT_DATE) AS days_remaining
FROM Permit p
JOIN Vehicle     v ON v.vehicle_id = p.vehicle_id
JOIN Users       u ON u.user_id    = v.user_id
JOIN ParkingZone z ON z.zone_id    = p.zone_id
WHERE p.expiry_date >= CURRENT_DATE;

-- View 2: Expired permits
CREATE VIEW vw_ExpiredPermits AS
SELECT
    p.permit_id,
    u.name          AS user_name,
    u.role,
    v.vehicle_number,
    z.zone_name,
    p.expiry_date,
    DATEDIFF(CURRENT_DATE, p.expiry_date) AS days_overdue
FROM Permit p
JOIN Vehicle     v ON v.vehicle_id = p.vehicle_id
JOIN Users       u ON u.user_id    = v.user_id
JOIN ParkingZone z ON z.zone_id    = p.zone_id
WHERE p.expiry_date < CURRENT_DATE;

-- View 3: Zone occupancy summary
CREATE VIEW vw_ZoneOccupancy AS
SELECT
    z.zone_id,
    z.zone_name,
    z.capacity,
    COUNT(p.permit_id)                        AS active_permits,
    z.capacity - COUNT(p.permit_id)           AS free_spaces,
    ROUND(COUNT(p.permit_id)/z.capacity*100,1) AS occupancy_pct
FROM ParkingZone z
LEFT JOIN Permit p ON p.zone_id = z.zone_id
    AND p.expiry_date >= CURRENT_DATE
GROUP BY z.zone_id, z.zone_name, z.capacity;

-- ─────────────────────────────────────────────────────────────
-- SECTION 4: STORED PROCEDURES
-- ─────────────────────────────────────────────────────────────

DELIMITER $$

-- Procedure 1: Issue a new permit
CREATE PROCEDURE sp_IssuePermit(
    IN  p_vehicle_id  INT,
    IN  p_zone_id     INT,
    IN  p_issue_date  DATE,
    IN  p_expiry_date DATE,
    OUT p_result      VARCHAR(100)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;

    -- Check if vehicle already has a permit
    SELECT COUNT(*) INTO v_exists
    FROM Permit WHERE vehicle_id = p_vehicle_id;

    IF v_exists > 0 THEN
        SET p_result = 'ERROR: Vehicle already has an active permit.';
    ELSEIF p_expiry_date <= p_issue_date THEN
        SET p_result = 'ERROR: Expiry date must be after issue date.';
    ELSE
        INSERT INTO Permit (vehicle_id, zone_id, issue_date, expiry_date)
        VALUES (p_vehicle_id, p_zone_id, p_issue_date, p_expiry_date);
        SET p_result = 'SUCCESS: Permit issued successfully.';
    END IF;
END$$

-- Procedure 2: Revoke a permit
CREATE PROCEDURE sp_RevokePermit(
    IN  p_permit_id INT,
    OUT p_result    VARCHAR(100)
)
BEGIN
    DECLARE v_exists INT DEFAULT 0;
    SELECT COUNT(*) INTO v_exists FROM Permit WHERE permit_id = p_permit_id;
    IF v_exists = 0 THEN
        SET p_result = 'ERROR: Permit not found.';
    ELSE
        DELETE FROM Permit WHERE permit_id = p_permit_id;
        SET p_result = 'SUCCESS: Permit revoked.';
    END IF;
END$$

-- Procedure 3: Register a new user
CREATE PROCEDURE sp_RegisterUser(
    IN p_name       VARCHAR(100),
    IN p_role       VARCHAR(50),
    IN p_department VARCHAR(100),
    IN p_phone      VARCHAR(20)
)
BEGIN
    INSERT INTO Users (name, role, department, phone)
    VALUES (p_name, p_role, p_department, p_phone);
    SELECT LAST_INSERT_ID() AS new_user_id;
END$$

DELIMITER ;

-- ─────────────────────────────────────────────────────────────
-- SECTION 5: TRIGGERS
-- ─────────────────────────────────────────────────────────────

DELIMITER $$

-- Trigger 1: Prevent issuing permit to a zone that is full
CREATE TRIGGER trg_CheckZoneCapacity
BEFORE INSERT ON Permit
FOR EACH ROW
BEGIN
    DECLARE v_capacity     INT;
    DECLARE v_active_count INT;

    SELECT capacity INTO v_capacity
    FROM ParkingZone WHERE zone_id = NEW.zone_id;

    SELECT COUNT(*) INTO v_active_count
    FROM Permit
    WHERE zone_id = NEW.zone_id
      AND expiry_date >= CURRENT_DATE;

    IF v_active_count >= v_capacity THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Zone is at full capacity. Cannot issue permit.';
    END IF;
END$$

-- Trigger 2: Log permit deletions (audit trail)
CREATE TABLE IF NOT EXISTS PermitAuditLog (
    log_id      INT AUTO_INCREMENT PRIMARY KEY,
    permit_id   INT,
    vehicle_id  INT,
    zone_id     INT,
    deleted_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    action_type VARCHAR(20) DEFAULT 'REVOKED'
);

CREATE TRIGGER trg_LogPermitDeletion
BEFORE DELETE ON Permit
FOR EACH ROW
BEGIN
    INSERT INTO PermitAuditLog (permit_id, vehicle_id, zone_id)
    VALUES (OLD.permit_id, OLD.vehicle_id, OLD.zone_id);
END$$

DELIMITER ;

-- ─────────────────────────────────────────────────────────────
-- SECTION 6: SEED DATA
-- ─────────────────────────────────────────────────────────────

INSERT INTO ParkingZone (zone_name, capacity) VALUES
    ('Zone A - Faculty Parking',  50),
    ('Zone B - Student Parking', 150),
    ('Zone C - Visitor Parking',  30);

INSERT INTO Users (name, role, department, phone) VALUES
    ('Dr. Ithisham Ullah', 'Teacher', 'Computer Science',      '03001000001'),
    ('Ali Ahmed',          'Student', 'Computer Science',      '03001234567'),
    ('Sara Khan',          'Student', 'Electrical Engineering','03009876543'),
    ('Azhan Masood',       'Student', 'Computer Science',      '03007654321'),
    ('Admin User',         'Admin',   'Administration',        '03000000001');

INSERT INTO Vehicle (vehicle_number, vehicle_type, user_id) VALUES
    ('LEA-0001', 'Car',        1),
    ('LEA-1234', 'Car',        2),
    ('LHR-5678', 'Motorcycle', 3),
    ('ISB-9999', 'Car',        4);

INSERT INTO Permit (vehicle_id, zone_id, issue_date, expiry_date) VALUES
    (1, 1, '2026-01-01', '2026-12-31'),
    (2, 2, '2026-01-15', '2026-06-30'),
    (3, 2, '2026-02-01', '2025-12-31'),
    (4, 2, '2026-04-01', '2026-12-31');

-- ─────────────────────────────────────────────────────────────
-- SECTION 7: SAMPLE QUERIES (Joins & Subqueries)
-- ─────────────────────────────────────────────────────────────

-- Query 1: All permits with full user and zone info (JOIN)
SELECT
    p.permit_id,
    u.name            AS owner,
    u.role,
    v.vehicle_number,
    v.vehicle_type,
    z.zone_name,
    p.issue_date,
    p.expiry_date,
    CASE WHEN p.expiry_date < CURRENT_DATE THEN 'Expired' ELSE 'Active' END AS status
FROM Permit p
JOIN Vehicle     v ON v.vehicle_id = p.vehicle_id
JOIN Users       u ON u.user_id    = v.user_id
JOIN ParkingZone z ON z.zone_id    = p.zone_id
ORDER BY p.expiry_date;

-- Query 2: Users who have NO vehicle registered (Subquery)
SELECT user_id, name, role, department
FROM Users
WHERE user_id NOT IN (
    SELECT DISTINCT user_id FROM Vehicle
);

-- Query 3: Vehicles with EXPIRED permits (Subquery)
SELECT v.vehicle_number, v.vehicle_type, u.name AS owner
FROM Vehicle v
JOIN Users u ON u.user_id = v.user_id
WHERE v.vehicle_id IN (
    SELECT vehicle_id FROM Permit
    WHERE expiry_date < CURRENT_DATE
);

-- Query 4: Zone with highest number of active permits (Aggregate + Subquery)
SELECT z.zone_name, COUNT(p.permit_id) AS active_count
FROM ParkingZone z
JOIN Permit p ON p.zone_id = z.zone_id
WHERE p.expiry_date >= CURRENT_DATE
GROUP BY z.zone_id, z.zone_name
HAVING COUNT(p.permit_id) = (
    SELECT MAX(cnt) FROM (
        SELECT COUNT(*) AS cnt
        FROM Permit
        WHERE expiry_date >= CURRENT_DATE
        GROUP BY zone_id
    ) AS sub
);

-- Query 5: Check expired permits (from proposal Section 10.4)
SELECT p.permit_id, v.vehicle_number, u.name, p.expiry_date,
       DATEDIFF(CURRENT_DATE, p.expiry_date) AS days_overdue
FROM Permit p
JOIN Vehicle v ON v.vehicle_id = p.vehicle_id
JOIN Users   u ON u.user_id    = v.user_id
WHERE p.expiry_date < CURRENT_DATE;

-- Query 6: Use procedure to issue permit
CALL sp_IssuePermit(4, 2, '2026-05-01', '2026-12-31', @result);
SELECT @result;

-- ─────────────────────────────────────────────────────────────
-- END OF SCHEMA
-- ─────────────────────────────────────────────────────────────
