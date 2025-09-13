#!/usr/bin/env python3
"""
EmotionAI Backend Testing Script
Tests all critical endpoints before AWS migration
"""

import requests
import json
import sys
from datetime import datetime
from typing import Dict, Any

# Configuration
BASE_URL = "http://localhost:8000"  # Change this to your backend URL
TEST_USER = {
    "username": "test_user",
    "password": "test_password123"
}

class Colors:
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    END = '\033[0m'

def print_test(name: str, passed: bool, message: str = ""):
    status = f"{Colors.GREEN}✓ PASSED{Colors.END}" if passed else f"{Colors.RED}✗ FAILED{Colors.END}"
    print(f"{status} - {name}")
    if message and not passed:
        print(f"  {Colors.YELLOW}→ {message}{Colors.END}")

def test_health_check():
    """Test basic health endpoint"""
    try:
        response = requests.get(f"{BASE_URL}/health/")
        passed = response.status_code == 200
        print_test("Health Check", passed, f"Status: {response.status_code}")
        return passed
    except Exception as e:
        print_test("Health Check", False, str(e))
        return False

def test_detailed_health():
    """Test detailed health endpoint"""
    try:
        response = requests.get(f"{BASE_URL}/health/detailed")
        passed = response.status_code == 200
        print_test("Detailed Health", passed, f"Status: {response.status_code}")
        return passed
    except Exception as e:
        print_test("Detailed Health", False, str(e))
        return False

def test_authentication():
    """Test authentication endpoints"""
    # Register
    try:
        register_data = {
            "username": TEST_USER["username"],
            "password": TEST_USER["password"],
            "email": f"{TEST_USER['username']}@test.com"
        }
        response = requests.post(f"{BASE_URL}/v1/api/auth/register", json=register_data)
        register_passed = response.status_code in [200, 201, 409]  # 409 if user exists
        print_test("User Registration", register_passed, f"Status: {response.status_code}")
    except Exception as e:
        print_test("User Registration", False, str(e))
        return None

    # Login
    try:
        login_data = {
            "username": TEST_USER["username"],
            "password": TEST_USER["password"]
        }
        response = requests.post(f"{BASE_URL}/v1/api/auth/login", json=login_data)
        login_passed = response.status_code == 200
        print_test("User Login", login_passed, f"Status: {response.status_code}")
        
        if login_passed:
            token = response.json().get("access_token")
            return token
    except Exception as e:
        print_test("User Login", False, str(e))
        return None

def test_protected_endpoints(token: str):
    """Test endpoints that require authentication"""
    headers = {"Authorization": f"Bearer {token}"}
    
    # Test emotional records
    try:
        response = requests.get(f"{BASE_URL}/v1/api/emotional_records/", headers=headers)
        passed = response.status_code == 200
        print_test("Get Emotional Records", passed, f"Status: {response.status_code}")
    except Exception as e:
        print_test("Get Emotional Records", False, str(e))

    # Test breathing sessions
    try:
        response = requests.get(f"{BASE_URL}/v1/api/breathing_sessions/", headers=headers)
        passed = response.status_code == 200
        print_test("Get Breathing Sessions", passed, f"Status: {response.status_code}")
    except Exception as e:
        print_test("Get Breathing Sessions", False, str(e))

    # Test breathing patterns
    try:
        response = requests.get(f"{BASE_URL}/v1/api/breathing_patterns/", headers=headers)
        passed = response.status_code == 200
        print_test("Get Breathing Patterns", passed, f"Status: {response.status_code}")
    except Exception as e:
        print_test("Get Breathing Patterns", False, str(e))

    # Test custom emotions
    try:
        response = requests.get(f"{BASE_URL}/v1/api/custom_emotions/", headers=headers)
        passed = response.status_code == 200
        print_test("Get Custom Emotions", passed, f"Status: {response.status_code}")
    except Exception as e:
        print_test("Get Custom Emotions", False, str(e))

def test_chat_endpoints(token: str):
    """Test AI chat endpoints"""
    headers = {"Authorization": f"Bearer {token}"}
    
    # Test agents list
    try:
        response = requests.get(f"{BASE_URL}/v1/api/agents", headers=headers)
        passed = response.status_code == 200
        print_test("List AI Agents", passed, f"Status: {response.status_code}")
    except Exception as e:
        print_test("List AI Agents", False, str(e))

    # Test chat message
    try:
        chat_data = {
            "agent_type": "therapy",
            "message": "Hello, this is a test message",
            "context": {}
        }
        response = requests.post(f"{BASE_URL}/v1/api/chat", headers=headers, json=chat_data)
        passed = response.status_code == 200
        print_test("Send Chat Message", passed, f"Status: {response.status_code}")
    except Exception as e:
        print_test("Send Chat Message", False, str(e))

def run_all_tests():
    """Run all backend tests"""
    print(f"\n{Colors.BLUE}🚀 EmotionAI Backend Test Suite{Colors.END}")
    print(f"{Colors.BLUE}{'='*40}{Colors.END}")
    print(f"Testing backend at: {BASE_URL}\n")
    
    # Basic health checks
    print(f"{Colors.YELLOW}1. Health Checks:{Colors.END}")
    health_ok = test_health_check()
    test_detailed_health()
    
    if not health_ok:
        print(f"\n{Colors.RED}❌ Backend is not responding. Please ensure it's running.{Colors.END}")
        return
    
    # Authentication
    print(f"\n{Colors.YELLOW}2. Authentication:{Colors.END}")
    token = test_authentication()
    
    if token:
        # Protected endpoints
        print(f"\n{Colors.YELLOW}3. Protected Endpoints:{Colors.END}")
        test_protected_endpoints(token)
        
        # Chat endpoints
        print(f"\n{Colors.YELLOW}4. AI Chat Endpoints:{Colors.END}")
        test_chat_endpoints(token)
    
    print(f"\n{Colors.BLUE}{'='*40}{Colors.END}")
    print(f"{Colors.GREEN}✅ Test suite completed!{Colors.END}\n")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        BASE_URL = sys.argv[1]
    run_all_tests()