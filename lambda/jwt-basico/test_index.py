import base64
import json
import time
import pytest
from index import handler


def crear_token(header: dict, payload: dict) -> str:
    h_b64 = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip("=")
    p_b64 = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
    s_b64 = "firma_falsa_perimetro_nivel_1"
    return f"{h_b64}.{p_b64}.{s_b64}"


def test_cors_options_permitido_sin_auth():
    event = {
        "requestContext": {"http": {"method": "OPTIONS"}},
        "headers": {},
    }
    res = handler(event, None)
    assert res == {"isAuthorized": True}


def test_rechaza_token_vacio():
    event = {
        "requestContext": {"http": {"method": "GET"}},
        "headers": {"authorization": ""},
    }
    res = handler(event, None)
    assert res == {"isAuthorized": False}


def test_rechaza_token_con_menos_o_mas_de_tres_segmentos():
    event = {
        "requestContext": {"http": {"method": "GET"}},
        "headers": {"authorization": "Bearer segmento1.segmento2"},
    }
    assert handler(event, None) == {"isAuthorized": False}

    event["headers"]["authorization"] = "Bearer seg1.seg2.seg3.seg4"
    assert handler(event, None) == {"isAuthorized": False}


def test_rechaza_algoritmo_none():
    header = {"alg": "none", "typ": "JWT"}
    payload = {
        "sub": "user-123",
        "iss": "https://auth.convivo.cl",
        "exp": time.time() + 3600,
    }
    token = crear_token(header, payload)
    event = {
        "requestContext": {"http": {"method": "GET"}},
        "headers": {"authorization": f"Bearer {token}"},
    }
    res = handler(event, None)
    assert res == {"isAuthorized": False}


def test_rechaza_algoritmo_vacio_o_ausente():
    header = {"typ": "JWT"}
    payload = {
        "sub": "user-123",
        "iss": "https://auth.convivo.cl",
        "exp": time.time() + 3600,
    }
    token = crear_token(header, payload)
    event = {
        "requestContext": {"http": {"method": "GET"}},
        "headers": {"authorization": f"Bearer {token}"},
    }
    assert handler(event, None) == {"isAuthorized": False}


def test_rechaza_token_expirado():
    header = {"alg": "RS256", "typ": "JWT"}
    payload = {
        "sub": "user-123",
        "iss": "https://auth.convivo.cl",
        "exp": time.time() - 100,
    }
    token = crear_token(header, payload)
    event = {
        "requestContext": {"http": {"method": "GET"}},
        "headers": {"authorization": f"Bearer {token}"},
    }
    assert handler(event, None) == {"isAuthorized": False}


def test_rechaza_token_sin_sub_o_sin_iss():
    header = {"alg": "RS256", "typ": "JWT"}
    payload_sin_sub = {
        "iss": "https://auth.convivo.cl",
        "exp": time.time() + 3600,
    }
    token1 = crear_token(header, payload_sin_sub)
    event1 = {
        "requestContext": {"http": {"method": "GET"}},
        "headers": {"authorization": f"Bearer {token1}"},
    }
    assert handler(event1, None) == {"isAuthorized": False}

    payload_sin_iss = {
        "sub": "user-123",
        "exp": time.time() + 3600,
    }
    token2 = crear_token(header, payload_sin_iss)
    event2 = {
        "requestContext": {"http": {"method": "GET"}},
        "headers": {"authorization": f"Bearer {token2}"},
    }
    assert handler(event2, None) == {"isAuthorized": False}


def test_permite_token_estructuralmente_valido():
    header = {"alg": "RS256", "typ": "JWT"}
    payload = {
        "sub": "user-123",
        "iss": "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_xyz",
        "exp": time.time() + 3600,
    }
    token = crear_token(header, payload)
    event = {
        "requestContext": {"http": {"method": "GET"}},
        "headers": {"authorization": f"Bearer {token}"},
    }
    assert handler(event, None) == {"isAuthorized": True}
