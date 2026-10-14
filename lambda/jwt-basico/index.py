"""Lambda Authorizer liviano (ERS.md RF-T.3 / TD-17).

Decodifica el JWT del header Authorization sin llamar a ningun JWKS: solo
valida que tenga tres segmentos decodificables y que `exp` no este vencido.
No resuelve issuer, audience ni rol -- esa resolucion completa (firma contra
el JWKS de Entra ID o Cognito segun `iss`, mas rol/ownership) la hace el bff
como reverse proxy (RF-T.4), no este authorizer.
"""

import base64
import json
import time


def _decodificar_segmento(segmento: str) -> dict:
    relleno = "=" * (-len(segmento) % 4)
    datos = base64.urlsafe_b64decode(segmento + relleno)
    return json.loads(datos)


def handler(event, _context):
    # Preflights CORS (OPTIONS) nunca incluyen credenciales por estándar W3C
    metodo = event.get("requestContext", {}).get("http", {}).get("method", "")
    if metodo.upper() == "OPTIONS":
        return {"isAuthorized": True}

    encabezado = event.get("headers", {}).get("authorization", "")
    token = encabezado[7:] if encabezado.lower().startswith("bearer ") else encabezado

    partes = token.split(".")
    if len(partes) != 3:
        return {"isAuthorized": False}

    try:
        encabezado_jwt = _decodificar_segmento(partes[0])
        carga = _decodificar_segmento(partes[1])
    except Exception:
        return {"isAuthorized": False}

    # Mitigacion critica: bloqueo estricto de algoritmo 'none' o ausente (A02 / CWE-327)
    alg = encabezado_jwt.get("alg")
    if not isinstance(alg, str) or not alg.strip() or alg.strip().lower() == "none":
        return {"isAuthorized": False}

    # Validacion sintactica de claims minimos requeridos
    sub = carga.get("sub")
    iss = carga.get("iss")
    if not isinstance(sub, str) or not sub.strip():
        return {"isAuthorized": False}
    if not isinstance(iss, str) or not iss.strip():
        return {"isAuthorized": False}

    exp = carga.get("exp")
    # Tolerancia de reloj de 30 segundos (clock skew)
    if not isinstance(exp, (int, float)) or exp < (time.time() - 30):
        return {"isAuthorized": False}

    return {"isAuthorized": True}
