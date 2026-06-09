# Guía SSO Google OAuth — AMS Platform

Configurar Single Sign-On con Google para que tus usuarios y los del cliente puedan loguearse con su cuenta Google corporativa (Workspace).

**Tiempo total**: ~1 hora la primera vez · ~10 min agregar clientes nuevos.

---

## ✅ Resultado esperado

```
Cliente abre app.tuempresa.cl
  → click "Login con Google"
  → autoriza con su Google Workspace
  → vuelve a la app logueado con rol asignado según email/dominio
```

---

## 📋 Paso 1 — Crear OAuth Client en Google Cloud (5 min)

1. Ir a: https://console.cloud.google.com/apis/credentials
2. Seleccionar tu proyecto (ej: `AMS-ROCCO-PROD`)
3. Click **"+ CREATE CREDENTIALS"** → **"OAuth client ID"**
4. Application type: **Web application**
5. Name: `AMS Platform OAuth`
6. **Authorized JavaScript origins**:
   ```
   https://app.tuempresa.cl
   https://*.tuempresa.cl    # si vas a tener multi-tenant por subdomain
   http://localhost:6700      # solo dev
   ```
7. **Authorized redirect URIs**:
   ```
   https://app.tuempresa.cl/api/auth/callback/google
   http://localhost:6700/api/auth/callback/google
   ```
8. **CREATE** → te muestra `client_id` y `client_secret`. Copialos.

⚠️ **NUNCA los pegues en el chat. Solo a tu .env / Doppler.**

---

## 📋 Paso 2 — Habilitar OAuth Consent Screen (10 min)

1. Ir a: https://console.cloud.google.com/apis/credentials/consent
2. User Type:
   - **Internal**: solo usuarios de tu Workspace (más seguro, recomendado para empezar)
   - **External**: cualquier usuario Google (necesita verificación de Google)
3. App information:
   - App name: `AMS Platform`
   - User support email: `soporte@tuempresa.cl`
   - App logo: tu logo (PNG cuadrado 120x120 mín)
   - Application home page: `https://app.tuempresa.cl`
   - Privacy policy link: `https://app.tuempresa.cl/privacy`
   - Terms of service link: `https://app.tuempresa.cl/terms`
4. Authorized domains: `tuempresa.cl`
5. Developer contact: `dev@tuempresa.cl`
6. **Scopes**:
   - `openid`
   - `email`
   - `profile`
7. Save and continue.

---

## 📋 Paso 3 — Instalar deps en backend (5 min)

```bash
cd /opt/ams/supply-chain-ams-agent/backend
npm install --save @fastify/oauth2 @fastify/jwt
```

---

## 📋 Paso 4 — Agregar OAuth route al backend (15 min)

Crear `backend/src/routes/auth-google.routes.ts`:

```typescript
import type { FastifyInstance } from "fastify";
import oauthPlugin from "@fastify/oauth2";
import { query } from "../database/db";
import { logger } from "../utils/logger";

const OAUTH_SCOPE = ["openid", "email", "profile"];

export async function googleAuthRoutes(app: FastifyInstance) {
  if (!process.env.GOOGLE_OAUTH_CLIENT_ID || !process.env.GOOGLE_OAUTH_CLIENT_SECRET) {
    logger.warn("Google OAuth: skipping registration (missing credentials)");
    return;
  }

  await app.register(oauthPlugin, {
    name: "googleOAuth2",
    scope: OAUTH_SCOPE,
    credentials: {
      client: {
        id: process.env.GOOGLE_OAUTH_CLIENT_ID,
        secret: process.env.GOOGLE_OAUTH_CLIENT_SECRET,
      },
      auth: oauthPlugin.GOOGLE_CONFIGURATION,
    },
    startRedirectPath: "/api/auth/google",
    callbackUri: `${process.env.PUBLIC_BASE_URL}/api/auth/callback/google`,
  });

  app.get("/api/auth/callback/google", async (req, reply) => {
    try {
      // @ts-expect-error - plugin agrega method
      const { token } = await app.googleOAuth2.getAccessTokenFromAuthorizationCodeFlow(req);

      // Obtener info del user
      const userInfoRes = await fetch("https://www.googleapis.com/oauth2/v2/userinfo", {
        headers: { Authorization: `Bearer ${token.access_token}` },
      });
      const userInfo = await userInfoRes.json() as { email: string; name: string; picture: string };

      // Validar dominio (si Internal)
      const allowedDomains = (process.env.GOOGLE_OAUTH_ALLOWED_DOMAINS ?? "").split(",").filter(Boolean);
      if (allowedDomains.length > 0 && !allowedDomains.some((d) => userInfo.email.endsWith(`@${d}`))) {
        return reply.code(403).send({ error: "Dominio no autorizado" });
      }

      // Upsert user en DB
      const { rows } = await query<{ id: string; role: string }>(
        `INSERT INTO users (email, name, role, is_active, auth_provider)
         VALUES ($1, $2, 'viewer', true, 'google')
         ON CONFLICT (email) DO UPDATE SET name = EXCLUDED.name, last_login_at = NOW()
         RETURNING id, role`,
        [userInfo.email, userInfo.name],
      );

      // Crear JWT propio
      // @ts-expect-error
      const sessionToken = app.jwt.sign({ userId: rows[0].id, email: userInfo.email, role: rows[0].role });

      // Set cookie + redirect a app
      reply.setCookie("ams_session", sessionToken, {
        path: "/", httpOnly: true, secure: true, sameSite: "lax",
        maxAge: 8 * 60 * 60, // 8h
      });
      return reply.redirect(`${process.env.PUBLIC_BASE_URL}/dashboard`);
    } catch (err) {
      logger.error({ err }, "Google OAuth callback failed");
      return reply.redirect("/login?error=oauth_failed");
    }
  });
}
```

---

## 📋 Paso 5 — Agregar botón en frontend (10 min)

En `platform/src/app/(public)/login/page.tsx`:

```tsx
<button onClick={() => window.location.href = `${process.env.NEXT_PUBLIC_AGENT_API_URL}/api/auth/google`}
  style={{ padding: 12, background: "white", color: "#333", border: "1px solid #ccc",
           borderRadius: 6, display: "flex", alignItems: "center", gap: 8, cursor: "pointer" }}>
  <img src="/google-icon.svg" width={20} alt="Google" />
  Continuar con Google
</button>
```

---

## 📋 Paso 6 — Variables de entorno (5 min)

Agregar a `.env.prod` del agent:

```bash
GOOGLE_OAUTH_CLIENT_ID=xxx.apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=GOCSPX-xxx
GOOGLE_OAUTH_ALLOWED_DOMAINS=tuempresa.cl,clienteejemplo.com
PUBLIC_BASE_URL=https://app.tuempresa.cl
JWT_SECRET=$(openssl rand -hex 32)
```

---

## 📋 Paso 7 — Rebuild + deploy (10 min)

```bash
ssh ams-prod
cd /opt/ams/supply-chain-ams-stack
git pull
bash scripts/deploy-env.sh prod
```

---

## 🧪 Verificación

1. Abrir https://app.tuempresa.cl/login
2. Click "Continuar con Google"
3. Autorizar
4. Deberías volver logueado a /dashboard
5. Verificar en DB:
   ```sql
   SELECT email, auth_provider, last_login_at FROM users
   ORDER BY last_login_at DESC LIMIT 5;
   ```

---

## 🆘 Troubleshooting

| Problema | Fix |
|---|---|
| `redirect_uri_mismatch` | Verificar callback URI exacto en Google Console |
| `invalid_client` | Verificar CLIENT_ID/SECRET correctos en .env |
| User logueado pero sin rol | Hacer UPDATE manual: `UPDATE users SET role='admin' WHERE email='admin@tuempresa.cl'` |
| Cookie no se mantiene | Verificar `secure: true` requiere HTTPS, en localhost usar `secure: false` |

---

## 👥 Agregar clientes nuevos

Cada cliente nuevo:

1. Cliente te da su dominio Google Workspace (ej: `clienteacme.com`)
2. Agregar a `GOOGLE_OAUTH_ALLOWED_DOMAINS` en .env:
   ```
   GOOGLE_OAUTH_ALLOWED_DOMAINS=tuempresa.cl,clienteacme.com
   ```
3. Restart backend
4. Cliente puede empezar a loguearse

---

## 📚 Para multi-tenant SaaS más avanzado

Ver:
- WorkOS (https://workos.com) - SSO managed
- Auth0 (https://auth0.com) - SSO + features extra
- Stack Auth (https://stack-auth.com) - open source alternative

Vale la pena considerar después del primer cliente real.
