import jwt
from functools import wraps
from flask import request, jsonify
from dotenv import load_dotenv
import os

load_dotenv()
SECRET_KEY = os.getenv('JWT_SECRET')

def token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        if not auth_header:
            return jsonify({'message': 'Access denied. No token provided.'}), 401
        try:
            token = auth_header.split(" ")[1]
        except IndexError:
            return jsonify({'message': 'Access denied. Invalid token format.'}), 401
        try:
            decoded = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
            request.user = decoded
        except jwt.ExpiredSignatureError:
            return jsonify({'message': 'Token has expired.'}), 403
        except jwt.InvalidTokenError:
            return jsonify({'message': 'Invalid token.'}), 403
        return f(*args, **kwargs)
    return decorated

def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        if not auth_header:
            return jsonify({'message': 'Access denied. No token provided.'}), 401
        try:
            token = auth_header.split(" ")[1]
        except IndexError:
            return jsonify({'message': 'Access denied. Invalid token format.'}), 401
        try:
            decoded = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
            if decoded.get('role') != 'admin':
                return jsonify({'message': 'Admin access required.'}), 403
            request.user = decoded
        except jwt.ExpiredSignatureError:
            return jsonify({'message': 'Token has expired.'}), 403
        except jwt.InvalidTokenError:
            return jsonify({'message': 'Invalid token.'}), 403
        return f(*args, **kwargs)
    return decorated

def optional_token_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get('Authorization')
        
        if auth_header:
            try:
                token = auth_header.split(" ")[1] 
                decoded = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
                request.user = decoded
            except (IndexError, jwt.ExpiredSignatureError, jwt.InvalidTokenError):
                request.user = None
        else:
            request.user = None
        
        return f(*args, **kwargs)
    return decorated