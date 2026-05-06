from flask import Flask, request, jsonify
import psycopg2
from auth_middleware import token_required
from flask_cors import CORS
import jwt
import datetime
from dotenv import load_dotenv
import os
from functools import wraps
from werkzeug.utils import secure_filename
import exifread
import bcrypt
from db import get_db_connection


processed_message= set()


app = Flask(__name__)
CORS(app)

load_dotenv()
JWT_SECRET = os.getenv('JWT_SECRET')


UPLOAD_FOLDER = "uploads"
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg"}

def allowed_file(filename):
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS

def extract_gps(file_path):
    try:
        with open(file_path, "rb") as f:
            tags = exifread.process_file(f)

        lat = tags.get("GPS GPSLatitude")
        lon = tags.get("GPS GPSLongitude")

        if lat and lon:
            return {
                "latitude": str(lat),
                "longitude": str(lon)
            }

        return None
    except Exception as e:
        print("EXIF error:", e)
        return None

@app.route('/auth/login', methods=['POST'])
def login():
    data = request.get_json() or {}
    
    email = data.get("email")
    password = data.get("password")

    if not email or not password:
        return jsonify({'message': 'Missing credentials.'}), 400
    
    con = get_db_connection()
    cur = con.cursor()

    try:
        cur.execute("SELECT userID, email, pass FROM users WHERE email=%s", (email,))
        user = cur.fetchone()

        if not user:
            return jsonify({'message': 'Invalid credentials.'}), 401

        user_id, user_email, password_hash = user

        stored_hash = password_hash.encode('utf-8') if isinstance(password_hash, str) else password_hash
        if not bcrypt.checkpw(password.encode('utf-8'), stored_hash):
            return jsonify({'message': 'Invalid credentials.'}), 401
        
        token = jwt.encode({
            "user_id": str(user_id),
            "email": user_email,
            'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=2)
        }, JWT_SECRET, algorithm="HS256")

        return jsonify({'token': token})
    except Exception as e:
        print("Login error:", e)
        return jsonify({'message': 'An error occurred during login.'}), 500
    finally:
        cur.close()
        con.close()

@app.route('/auth/register', methods=['POST'])
def register():
    data = request.get_json() or {}
    
    email = data.get("email")
    password = data.get("password")
    username = data.get("userName")


    if not email or not password or not username:
        return jsonify({'message': 'Missing credentials.'}), 400
    
    hashedPassword = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute(
            "INSERT INTO users (userName, email, pass) VALUES (%s, %s, %s) RETURNING userID, email",
            (username, email, hashedPassword)
        )
        user = cur.fetchone()
        conn.commit()

        token = jwt.encode({
            "user_id": str(user[0]),
            "email":   user[1],
            "exp":     datetime.datetime.utcnow() + datetime.timedelta(hours=2)
        }, JWT_SECRET, algorithm="HS256")

        return jsonify({
            'message': 'User registered successfully.',
            'token': token
        }), 201

    except psycopg2.errors.UniqueViolation:
        conn.rollback()
        return jsonify({'message': 'User already exists.'}), 400

    except Exception as e:
        conn.rollback()
        # Log the actual error for debugging
        print("Registration error:", e)
        return jsonify({'message': 'Registration failed.'}), 500

    finally:
        cur.close()
        conn.close()

        
@app.route("/report", methods=["POST"])
@token_required
def create_report():
    data = request.json or {}

    required = ["report_type", "latitude", "longitude", "urgency_level", "sent_mode"]

    if not all(field in data for field in required):
        return jsonify({"error": "Missing fields"}), 400
    
    report_type = data["report_type"].upper()

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("""
            INSERT INTO emergencyReports 
            (reportID, userID, report_type, description, latitude, longitude, urgency_level, status, sent_mode, created_at)
            VALUES (gen_random_uuid(), %s,%s,%s,%s,%s,%s,'PENDING',%s,NOW())
            RETURNING *
        """, (
            request.user["user_id"],
            report_type,
            data.get("description"),
            data["latitude"],
            data["longitude"],
            data["urgency_level"],
            data["sent_mode"]
        ))

        report = cur.fetchone()
        conn.commit()
        
        return jsonify({"message": "Report created", "report": report}), 201

    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    
    finally:
        cur.close()
        conn.close()
    
@app.route("/photo/<reportID>", methods=["POST"])
@token_required
def upload_photo(reportID):

    if "photo" not in request.files:
        return jsonify({"error": "No file uploaded"}), 400

    file = request.files["photo"]

    if not allowed_file(file.filename):
        return jsonify({"error": "Invalid file type"}), 400

    filename = secure_filename(f"{datetime.datetime.now().timestamp()}_{file.filename}")
    filepath = os.path.join(UPLOAD_FOLDER, filename)
    file.save(filepath)

    gps = extract_gps(filepath)

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("""
            INSERT INTO reportPhotos (reportID, photo_path, uploaded_at)
            VALUES (%s, %s, NOW())
            RETURNING *
        """, (reportID, filepath))

        conn.commit()

        return jsonify({
            "message": "Photo uploaded",
            "gps": gps
        }), 201

    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()
    
@app.route("/userreport", methods=["GET"])
@token_required
def get_userreports():
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT * FROM emergencyReports
        WHERE userID = %s
        ORDER BY
            CASE urgency_level
                WHEN 'HIGH' THEN 1
                WHEN 'MEDIUM' THEN 2
                ELSE 3
            END,
            created_at DESC
    """, (request.user["user_id"],))

    data = cur.fetchall()

    cur.close()
    conn.close()

    return jsonify({"reports": data})
    
    

@app.route("/status/<reportID>", methods=["PUT"])
@token_required
def update_status(reportID):
    data = request.json or {}
    status = data.get("status")

    if status not in ["PENDING", "IN_PROGRESS", "RESOLVED"]:
        return jsonify({"error": "Invalid status"}), 400

    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("""
            UPDATE emergencyReports
            SET status=%s
            WHERE reportID=%s AND userID=%s
            RETURNING *
    """, (status, reportID, request.user["user_id"]))

        updated = cur.fetchone()
        conn.commit()
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()

    return jsonify({"report": updated})

@app.route("/report/<reportID>", methods=["DELETE"])
@token_required
def delete_report(reportID):
    conn = get_db_connection()
    cur = conn.cursor()

    try:
        cur.execute("""
            DELETE FROM emergencyReports
            WHERE reportID=%s AND userID=%s
            RETURNING reportID
        """, (reportID, request.user["user_id"]))

        result = cur.fetchone()
        conn.commit()
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        cur.close()
        conn.close()


    if not result:
        return jsonify({"error": "Not found"}), 404

    return jsonify({"message": "Deleted"})

@app.route("/sync", methods=["POST"])
@token_required
def sync():
    data = request.json or {}
    reports = data.get("reports", [])

    conn = get_db_connection()
    cur = conn.cursor()

    results = {"saved": 0, "duplicates": 0, "errors": 0}

    for r in reports:
        try:
            if r.get("ttl", 1) <= 0:
                continue

            if r["reportID"] in processed_message:
                results["duplicates"] += 1
                continue

            cur.execute("SELECT reportID FROM emergencyReports WHERE reportID=%s", (r["reportID"],))

            if cur.fetchone():
                results["duplicates"] += 1
                continue

            report_type = r["report_type"].upper()

            cur.execute("""
                INSERT INTO emergencyReports
                (reportID, userID, report_type, description, latitude, longitude, urgency_level, status, sent_mode, created_at)
                VALUES (%s,%s,%s,%s,%s,%s,%s,'PENDING',%s,%s)
            """, (
                r["reportID"],
                request.user["user_id"],
                report_type,
                r["description"],
                r["latitude"],
                r["longitude"],
                r["urgency_level"],
                r["sent_mode"],
                r["created_at"]

            ))
            processed_message.add(r["reportID"])

            results["saved"] += 1

            
           
        except Exception as e:
            print("Sync error:", e)
            results["errors"] += 1

    conn.commit()
    cur.close()
    conn.close()

    return jsonify(results)

@app.route("/alerts", methods=["GET"])
def alerts():
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("SELECT * FROM alerts ORDER BY created_at DESC")

    data = cur.fetchall()

    cur.close()
    conn.close()

    return jsonify({"alerts": data})

@app.route('/protected', methods=['GET'])
@token_required
def protected():
    return jsonify({'message': 'This is a protected route.', 'user': request.user}) 

@app.route('/mesh/upload', methods=['POST'])
@token_required
def upload_mesh():
    data = request.get_json() or {}
    messages = data.get("messages", [])

    request._cached_json = {"reports": messages}
    return sync()

@app.route("/mesh/download", methods=["GET"])
@token_required
def download_mesh():
    conn = get_db_connection()
    cur = conn.cursor()

    cur.execute("""
        SELECT * FROM emergencyReports
        WHERE created_at > NOW() - INTERVAL '1 hour'
        ORDER BY
            CASE urgency_level
                WHEN 'HIGH' THEN 1
                WHEN 'MEDIUM' THEN 2
                ELSE 3
            END,
            created_at DESC
    """)

    data = cur.fetchall()

    cur.close()
    conn.close()

    return jsonify({"reports": data})
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)