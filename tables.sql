CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    userID        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    userName          VARCHAR(100)  NOT NULL,
    email         VARCHAR(150)  UNIQUE NOT NULL,
    pass          VARCHAR (255)  NOT NULL,
    phone_number  VARCHAR(20),
    lastActive    TIMESTAMP     DEFAULT NOW(),
    created_at    TIMESTAMP     DEFAULT NOW()
);

CREATE TABLE risk_zones (
    zoneID        UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    zone_name     VARCHAR(150)  NOT NULL,
    zone_code     VARCHAR(20)   UNIQUE NOT NULL,
    risk_level    VARCHAR(20)   NOT NULL CHECK (risk_level IN ('LOW', 'MODERATE', 'HIGH')),
    boundary      JSON          NOT NULL,
    parish        VARCHAR(100)  NOT NULL,
    description   TEXT,
    danger_score  DECIMAL(5,2)  DEFAULT 0.00,
    threat_level  VARCHAR(20)   DEFAULT 'LOW' CHECK (threat_level IN ('LOW', 'MODERATE', 'HIGH')),
    last_escalated TIMESTAMP,
    created_at    TIMESTAMP     DEFAULT NOW(),
    updated_at    TIMESTAMP     DEFAULT NOW()
);

CREATE TABLE userLocations (
    locationID     UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    userID         UUID         NOT NULL REFERENCES users(userID) ON DELETE CASCADE,
    latitude       DECIMAL(9,6) NOT NULL,
    longitude      DECIMAL(9,6) NOT NULL,
    location       VARCHAR(255),
    riskLevel      VARCHAR(20)  DEFAULT 'LOW' CHECK (riskLevel IN ('LOW', 'MODERATE', 'HIGH')),
    zoneRiskID     UUID         REFERENCES risk_zones(zoneID) ON DELETE SET NULL,
    timestamped_at TIMESTAMP    DEFAULT NOW()
);

CREATE TABLE emergencyReports (
    reportID      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    userID        UUID         NOT NULL REFERENCES users(userID) ON DELETE CASCADE,
    report_type   VARCHAR(50)  NOT NULL CHECK (report_type IN (
                      'TRAPPED_PERSON',
                      'INJURY',
                      'FLOODING',
                      'BLOCKED_ROAD',
                      'STRUCTURAL_DAMAGE',
                      'MISSING_PERSON',
                      'OTHER'
                  )),
    description   TEXT,
    latitude      DECIMAL(9,6),
    longitude     DECIMAL(9,6),
    urgency_level VARCHAR(20)  NOT NULL CHECK (urgency_level IN ('LOW', 'MEDIUM', 'HIGH')),
    status        VARCHAR(20)  DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'IN_PROGRESS', 'RESOLVED')),
    sent_mode     VARCHAR(20)  NOT NULL CHECK (sent_mode IN ('INTERNET', 'MESH', 'GATEWAY')),
    created_at    TIMESTAMP    DEFAULT NOW(),
    resolved_at   TIMESTAMP
);

CREATE TABLE reportPhotos (
    photoID      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reportID     UUID         NOT NULL REFERENCES emergencyReports(reportID) ON DELETE CASCADE,
    photo_path   VARCHAR(500) NOT NULL,
    uploaded_at  TIMESTAMP    DEFAULT NOW()
);

