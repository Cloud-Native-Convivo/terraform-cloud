"""Lambda Authorizer liviano (mvp.md RF-T.3 / TD-17).

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
        # DEBUG temporal: diagnostico del 401 "sesion expirada/invalida"
        print(f"DEBUG jwt-basico: sin token o malformado, header_len={len(encabezado)}, partes={len(partes)}")
        return {"isAuthorized": False}

    try:
        carga = _decodificar_segmento(partes[1])
    except Exception as exc:
        print(f"DEBUG jwt-basico: fallo decodificando payload: {exc}")
        return {"isAuthorized": False}

    exp = carga.get("exp")
    if not isinstance(exp, (int, float)) or exp < time.time():
        print(f"DEBUG jwt-basico: token expirado o sin exp, exp={exp}, ahora={time.time()}, iss={carga.get('iss')}, aud={carga.get('aud')}")
        return {"isAuthorized": False}

    return {"isAuthorized": True}
