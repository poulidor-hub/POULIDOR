"""
Registre des tools MCP exposes par le serveur Hub Tools.
Chaque tool utilise hub_client.call_hub_endpoint() pour communiquer avec le HUB.
"""
import json
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from mcp.types import Tool, TextContent
from backend.hub_client import hub_client

# ============================================================
# TOOL DEFINITIONS
# ============================================================

TOOLS = [
    # --- Health ---
    Tool(
        name="hub_health",
        description="Verifie l'etat de sante du HUB (health check).",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    Tool(
        name="hub_config",
        description="Recupere la configuration runtime du HUB (feature flags).",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    Tool(
        name="hub_system_time",
        description="Recupere l'heure systeme UTC du serveur HUB.",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    # --- Raw call ---
    Tool(
        name="hub_raw_call",
        description="Appelle un endpoint arbitraire de l'API Hub avec authentification M2M.",
        inputSchema={
            "type": "object",
            "properties": {
                "endpoint": {"type": "string", "description": "Endpoint Hub (ex: /api/health)"},
                "path": {"type": "string", "description": "Alias pour endpoint"},
                "method": {"type": "string", "description": "Methode HTTP (GET, POST, PUT, DELETE)", "default": "GET"},
                "body": {"type": "object", "description": "Corps JSON (POST/PUT)"},
            },
            "required": [],
        },
    ),
    # --- App Management ---
    Tool(
        name="hub_app_list",
        description="Liste toutes les applications enregistrees sur le HUB (filtre par role si non-admin).",
        inputSchema={
            "type": "object",
            "properties": {
                "page": {"type": "integer", "description": "Numero de page (default 1)"},
                "per_page": {"type": "integer", "description": "Elements par page (default 20)"},
                "search": {"type": "string", "description": "Recherche par nom ou slug"},
            },
            "required": [],
        },
    ),
    Tool(
        name="hub_app_get",
        description="Recupere les details d'une application par son ID.",
        inputSchema={
            "type": "object",
            "properties": {
                "app_id": {"type": "integer", "description": "ID de l'application"},
            },
            "required": ["app_id"],
        },
    ),
    Tool(
        name="hub_app_create",
        description="Cree une nouvelle application sur le HUB (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "slug": {"type": "string", "description": "Slug unique"},
                "name": {"type": "string", "description": "Nom affiche"},
                "description": {"type": "string", "description": "Description (optionnel)"},
                "is_shared_service": {"type": "boolean", "description": "Service partage M2M"},
            },
            "required": ["slug", "name"],
        },
    ),
    Tool(
        name="hub_app_update",
        description="Met a jour une application sur le HUB (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "app_id": {"type": "integer", "description": "ID de l'app a modifier"},
                "name": {"type": "string", "description": "Nouveau nom"},
                "description": {"type": "string", "description": "Nouvelle description"},
            },
            "required": ["app_id"],
        },
    ),
    Tool(
        name="hub_app_delete",
        description="Supprime une application du HUB (admin requis, cascade SA + credentials).",
        inputSchema={
            "type": "object",
            "properties": {
                "app_id": {"type": "integer", "description": "ID de l'app a supprimer"},
            },
            "required": ["app_id"],
        },
    ),
    Tool(
        name="hub_app_toggle_active",
        description="Active ou desactive une application (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "app_id": {"type": "integer", "description": "ID de l'application"},
            },
            "required": ["app_id"],
        },
    ),
    Tool(
        name="hub_app_register",
        description="Auto-enregistre l'application courante (celle du template) aupres du HUB.",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    Tool(
        name="hub_app_get_credentials",
        description="Lit les credentials M2M locales de l'application courante.",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    Tool(
        name="hub_app_regenerate_secret",
        description="Regenere le client secret de l'application aupres du HUB.",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    Tool(
        name="hub_app_set_users",
        description="Assigne des utilisateurs a une application avec leurs roles (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "app_id": {"type": "integer", "description": "ID de l'application"},
                "user_ids": {"type": "array", "items": {"type": "integer"}, "description": "Liste des IDs utilisateurs"},
            },
            "required": ["app_id", "user_ids"],
        },
    ),
    Tool(
        name="hub_app_toggle_shared",
        description="Active/desactive le flag IS_SHARED d'une application (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "app_id": {"type": "integer"},
                "shared": {"type": "boolean"},
            },
            "required": ["app_id", "shared"],
        },
    ),
    Tool(
        name="hub_app_approve",
        description="Approuve ou rejette une application en attente (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "app_slug": {"type": "string", "description": "Slug de l'application en attente"},
                "approved": {"type": "boolean", "description": "True pour approuver, False pour rejeter"},
            },
            "required": ["app_slug", "approved"],
        },
    ),
    Tool(
        name="hub_app_docker_scan",
        description="Scanne les conteneurs Docker accessibles depuis le HUB (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    # --- User Management ---
    Tool(
        name="hub_user_list",
        description="Liste les utilisateurs du HUB (pagine, admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "page": {"type": "integer", "description": "Page (default 1)"},
                "per_page": {"type": "integer", "description": "Par page (default 20)"},
                "search": {"type": "string", "description": "Recherche par username ou email"},
            },
            "required": [],
        },
    ),
    Tool(
        name="hub_user_get",
        description="Recupere les details d'un utilisateur par son ID.",
        inputSchema={
            "type": "object",
            "properties": {"user_id": {"type": "integer", "description": "ID utilisateur"}},
            "required": ["user_id"],
        },
    ),
    Tool(
        name="hub_user_create",
        description="Cree un nouvel utilisateur sur le HUB (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "username": {"type": "string"},
                "password": {"type": "string"},
                "email": {"type": "string"},
                "is_admin": {"type": "boolean", "description": "Role admin global"},
            },
            "required": ["username", "password", "email"],
        },
    ),
    Tool(
        name="hub_user_update",
        description="Met a jour un utilisateur (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "user_id": {"type": "integer"},
                "username": {"type": "string"},
                "email": {"type": "string"},
                "is_active": {"type": "boolean"},
            },
            "required": ["user_id"],
        },
    ),
    Tool(
        name="hub_user_delete",
        description="Supprime un utilisateur (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {"user_id": {"type": "integer"}},
            "required": ["user_id"],
        },
    ),
    Tool(
        name="hub_user_reset_password",
        description="Force la reinitialisation du mot de passe d'un utilisateur (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "user_id": {"type": "integer"},
                "new_password": {"type": "string", "description": "Nouveau mot de passe"},
            },
            "required": ["user_id", "new_password"],
        },
    ),
    Tool(
        name="hub_user_set_app_roles",
        description="Assigne des roles d'application a un utilisateur (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "user_id": {"type": "integer"},
                "app_roles": {"type": "object", "description": "Mapping {app_slug: role}"},
            },
            "required": ["user_id", "app_roles"],
        },
    ),
    Tool(
        name="hub_user_bulk_create",
        description="Cree plusieurs utilisateurs en masse (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "users": {"type": "array", "items": {"type": "object", "properties": {"username": {"type": "string"}, "password": {"type": "string"}, "email": {"type": "string"}}}},
            },
            "required": ["users"],
        },
    ),
    Tool(
        name="hub_user_bulk_roles",
        description="Met a jour les roles de plusieurs utilisateurs en masse (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "updates": {"type": "array", "items": {"type": "object", "properties": {"user_id": {"type": "integer"}, "role": {"type": "string"}}}},
            },
            "required": ["updates"],
        },
    ),
    # --- Auth & Tokens ---
    Tool(
        name="hub_auth_login",
        description="Authentifie un utilisateur et recupere un token JWT (password grant).",
        inputSchema={
            "type": "object",
            "properties": {
                "username": {"type": "string"},
                "password": {"type": "string"},
            },
            "required": ["username", "password"],
        },
    ),
    Tool(
        name="hub_auth_me",
        description="Recupere les informations de l'utilisateur courant via le token M2M.",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    Tool(
        name="hub_auth_get_m2m_token",
        description="Obtient un token M2M pour l'application courante (client_credentials).",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    Tool(
        name="hub_auth_get_jwks",
        description="Recupere le JWKS (JSON Web Key Set) du HUB pour valider les tokens JWT.",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    Tool(
        name="hub_auth_token_introspect",
        description="Introspecte un token JWT (RFC 7662, admin ou SA requis).",
        inputSchema={
            "type": "object",
            "properties": {"token": {"type": "string", "description": "Token JWT a introspecter"}},
            "required": ["token"],
        },
    ),
    Tool(
        name="hub_auth_create_bootstrap_token",
        description="Cree un token bootstrap pour une application (admin requis).",
        inputSchema={
            "type": "object",
            "properties": {
                "app_slug": {"type": "string", "description": "Slug de l'application cible"},
                "scope": {"type": "string", "description": "Scope du token (ex: register)"},
            },
            "required": ["app_slug", "scope"],
        },
    ),
    Tool(
        name="hub_auth_list_bootstrap_tokens",
        description="Liste les tokens bootstrap existants (admin requis, sans la valeur brute).",
        inputSchema={
            "type": "object",
            "properties": {},
            "required": [],
        },
    ),
    # --- Backup & Restore ---
    Tool(name="hub_backup_export_env", description="Exporte l'environnement complet du HUB (admin requis).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_backup_import_env", description="Importe un environnement dans le HUB (admin requis).", inputSchema={"type": "object", "properties": {"data": {"type": "object"}}, "required": ["data"]}),
    Tool(name="hub_backup_list", description="Liste les backups d'une application (SA ou admin).", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}}, "required": ["app_slug"]}),
    Tool(name="hub_backup_get_latest", description="Dernier backup d'une application.", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}}, "required": ["app_slug"]}),
    Tool(name="hub_backup_download", description="Telecharge un backup ZIP (SA ou admin).", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}, "backup_id": {"type": "integer"}}, "required": ["app_slug", "backup_id"]}),
    Tool(name="hub_backup_config_get", description="Lit la config de backup d'une app (admin).", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}}, "required": ["app_slug"]}),
    Tool(name="hub_backup_config_update", description="Modifie la config de backup (admin).", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}, "config": {"type": "object"}}, "required": ["app_slug", "config"]}),
    Tool(name="hub_backup_delete", description="Supprime un backup (admin).", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}, "backup_id": {"type": "integer"}}, "required": ["app_slug", "backup_id"]}),
    Tool(name="hub_backup_restore", description="Restaure depuis un backup (admin).", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}, "backup_id": {"type": "integer"}}, "required": ["app_slug", "backup_id"]}),
    Tool(name="hub_backup_stats", description="Statistiques globales des backups (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_backup_orphans_list", description="Liste les backups orphelins (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_backup_trigger", description="Declenche un backup manuel (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    # --- Messages ---
    Tool(name="hub_message_send", description="Envoie un message (cible ou broadcast, admin).", inputSchema={"type": "object", "properties": {"title": {"type": "string"}, "target_usernames": {"type": "array", "items": {"type": "string"}}, "body": {"type": "string"}, "priority": {"type": "string", "enum": ["info", "warning", "urgent"]}}, "required": ["title", "target_usernames"]}),
    Tool(name="hub_message_list", description="Liste les messages (admin, pagine).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_message_my_list", description="Mes messages (utilisateur courant).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_message_my_unread_count", description="Nombre de messages non lus.", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_message_read", description="Marque un message comme lu.", inputSchema={"type": "object", "properties": {"message_id": {"type": "integer"}}, "required": ["message_id"]}),
    Tool(name="hub_message_stats", description="Statistiques des messages (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_message_m2m_send", description="Envoie un message M2M.", inputSchema={"type": "object", "properties": {"title": {"type": "string"}, "target_usernames": {"type": "array", "items": {"type": "string"}}, "body": {"type": "string"}, "priority": {"type": "string"}}, "required": ["title", "target_usernames"]}),
    # --- Audit ---
    Tool(name="hub_audit_logs", description="Logs d'audit (pagine, filtrable).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_audit_sessions", description="Sessions actives (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_audit_sessions_history", description="Historique des sessions.", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_audit_stats", description="Statistiques globales (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_audit_errors", description="Liste des erreurs (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_audit_errors_stats", description="Statistiques d'erreurs (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_audit_error_detail", description="Detail d'une erreur avec stack trace.", inputSchema={"type": "object", "properties": {"error_id": {"type": "integer"}}, "required": ["error_id"]}),
    Tool(name="hub_audit_errors_acknowledge", description="Acquitter toutes les erreurs.", inputSchema={"type": "object", "properties": {}, "required": []}),
    # --- Docs ---
    Tool(name="hub_docs_get", description="Documentation d'integration (full ou section).", inputSchema={"type": "object", "properties": {"section": {"type": "string"}}, "required": []}),
    Tool(name="hub_docs_sections", description="Liste les sections de documentation.", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_changelog_get", description="Changelog (filtrable par version).", inputSchema={"type": "object", "properties": {"since": {"type": "string"}, "latest": {"type": "boolean"}, "format": {"type": "string"}}, "required": []}),
    Tool(name="hub_changelog_diff", description="Diff entre deux versions.", inputSchema={"type": "object", "properties": {"from_version": {"type": "string"}}, "required": ["from_version"]}),
    # --- Discovery ---
    Tool(name="hub_discover_services", description="Decouvre les services partages via le Hub.", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_call_service", description="Appelle un endpoint d'un service decouvert.", inputSchema={"type": "object", "properties": {"service_slug": {"type": "string"}, "endpoint": {"type": "string"}, "method": {"type": "string", "default": "GET"}}, "required": ["service_slug", "endpoint"]}),
    Tool(name="hub_discovery_proxy", description="Proxy admin vers une app.", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}, "endpoint": {"type": "string"}}, "required": ["app_slug", "endpoint"]}),
    # --- Design ---
    Tool(name="hub_design_manifest", description="Manifeste courant du design system.", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_design_status", description="Statut de deploiement du design system (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_design_upload", description="Uploader un tarball design system (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    # --- Admin ---
    Tool(name="hub_admin_info", description="Dashboard info HUB (hostname, version, uptime).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_admin_settings", description="Lister les settings (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_admin_ports_status", description="Statut du pool de ports (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_admin_dns_status", description="Resolution DNS des apps (admin).", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_pki_ca_info", description="Infos de la CA interne.", inputSchema={"type": "object", "properties": {}, "required": []}),
    Tool(name="hub_pki_list_certs", description="Certificats d'une app.", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}}, "required": ["app_slug"]}),
    Tool(name="hub_pki_revoke_cert", description="Revoquer un certificat (admin).", inputSchema={"type": "object", "properties": {"app_slug": {"type": "string"}, "cert_id": {"type": "integer"}}, "required": ["app_slug", "cert_id"]}),
]

# ============================================================
# HANDLER DISPATCH
# ============================================================

HANDLERS = {
    "hub_health": lambda args: hub_client.call_hub_endpoint("/api/health", method="GET"),
    "hub_config": lambda args: hub_client.call_hub_endpoint("/api/config", method="GET"),
    "hub_system_time": lambda args: hub_client.call_hub_endpoint("/api/system/time", method="GET"),
    "hub_raw_call": lambda args: hub_client.call_hub_endpoint(
        args.get("path", args.get("endpoint", "/api/health")),
        method=args.get("method", "GET"),
        json=args.get("body"),
    ),
    # --- App Management ---
    "hub_app_list": lambda args: hub_client.call_hub_endpoint("/api/apps/", method="GET"),
    "hub_app_get": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_id']}", method="GET"),
    "hub_app_create": lambda args: hub_client.call_hub_endpoint("/api/apps/", method="POST", json={"slug": args["slug"], "name": args["name"], "description": args.get("description", ""), "is_shared_service": args.get("is_shared_service", False)}),
    "hub_app_update": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_id']}", method="PATCH", json={k: v for k, v in args.items() if k != "app_id"}),
    "hub_app_delete": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_id']}", method="DELETE"),
    "hub_app_toggle_active": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_id']}/toggle-active", method="PATCH"),
    "hub_app_register": lambda args: _handle_register(args),
    "hub_app_get_credentials": lambda args: _handle_get_credentials(args),
    "hub_app_regenerate_secret": lambda args: _handle_regenerate_secret(args),
    "hub_app_set_users": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_id']}/users", method="POST", json=args["user_ids"]),
    "hub_app_toggle_shared": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_id']}/shared", method="PUT", params={"is_shared": args["shared"]}),
    "hub_app_approve": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_slug']}/approve", method="POST", json={"approve": args["approved"]}),
    "hub_app_docker_scan": lambda args: hub_client.call_hub_endpoint("/api/apps/docker/scan", method="GET"),
    # --- User Management ---
    "hub_user_list": lambda args: hub_client.call_hub_endpoint("/api/users/", method="GET"),
    "hub_user_get": lambda args: hub_client.call_hub_endpoint(f"/api/users/{args['user_id']}", method="GET"),
    "hub_user_create": lambda args: hub_client.call_hub_endpoint("/api/users/", method="POST", json={k: v for k, v in args.items()}),
    "hub_user_update": lambda args: hub_client.call_hub_endpoint(f"/api/users/{args['user_id']}", method="PATCH", json={k: v for k, v in args.items() if k != "user_id"}),
    "hub_user_delete": lambda args: hub_client.call_hub_endpoint(f"/api/users/{args['user_id']}", method="DELETE"),
    "hub_user_reset_password": lambda args: hub_client.call_hub_endpoint(f"/api/users/{args['user_id']}/admin/reset-password", method="POST", json={"new_password": args["new_password"]}),
    "hub_user_set_app_roles": lambda args: hub_client.call_hub_endpoint(f"/api/users/{args['user_id']}/apps", method="POST", json=args["app_roles"]),
    "hub_user_bulk_create": lambda args: hub_client.call_hub_endpoint("/api/users/bulk/create", method="POST", json=args["users"]),
    "hub_user_bulk_roles": lambda args: hub_client.call_hub_endpoint("/api/users/bulk/roles", method="POST", json=args["updates"]),
    # --- Auth & Tokens ---
    "hub_auth_login": lambda args: hub_client.call_hub_endpoint("/api/auth/token", method="POST", data={"grant_type": "password", "username": args["username"], "password": args["password"]}),
    "hub_auth_me": lambda args: hub_client.call_hub_endpoint("/api/auth/me", method="GET"),
    "hub_auth_get_m2m_token": lambda args: _handle_get_m2m_token(args),
    "hub_auth_get_jwks": lambda args: _handle_get_jwks(args),
    "hub_auth_token_introspect": lambda args: hub_client.call_hub_endpoint("/api/auth/token/introspect", method="POST", json={"token": args["token"]}),
    "hub_auth_create_bootstrap_token": lambda args: hub_client.call_hub_endpoint("/api/apps/bootstrap-tokens", method="POST", json={"app_slug": args["app_slug"], "scope": args["scope"]}),
    "hub_auth_list_bootstrap_tokens": lambda args: hub_client.call_hub_endpoint("/api/apps/bootstrap-tokens", method="GET"),
    # --- Backup & Restore ---
    "hub_backup_export_env": lambda args: hub_client.call_hub_endpoint("/api/admin/backup/export", method="GET"),
    "hub_backup_import_env": lambda args: hub_client.call_hub_endpoint("/api/admin/backup/import", method="POST", json=args["data"]),
    "hub_backup_list": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_slug']}/backup", method="GET"),
    "hub_backup_get_latest": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_slug']}/backup/latest", method="GET"),
    "hub_backup_download": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_slug']}/backup/{args['backup_id']}/export", method="GET"),
    "hub_backup_config_get": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_slug']}/backup/config", method="GET"),
    "hub_backup_config_update": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_slug']}/backup/config", method="PUT", json=args["config"]),
    "hub_backup_delete": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_slug']}/backup/{args['backup_id']}", method="DELETE"),
    "hub_backup_restore": lambda args: hub_client.call_hub_endpoint(f"/api/apps/{args['app_slug']}/backup/{args['backup_id']}/restore", method="POST"),
    "hub_backup_stats": lambda args: hub_client.call_hub_endpoint("/api/admin/backups/stats", method="GET"),
    "hub_backup_orphans_list": lambda args: hub_client.call_hub_endpoint("/api/admin/backups/orphans", method="GET"),
    "hub_backup_trigger": lambda args: hub_client.call_hub_endpoint("/api/apps/backup/trigger", method="POST"),
    # --- Messages ---
    "hub_message_send": lambda args: hub_client.call_hub_endpoint("/api/messages/send", method="POST", json={k: v for k, v in args.items()}),
    "hub_message_list": lambda args: hub_client.call_hub_endpoint("/api/messages/", method="GET"),
    "hub_message_my_list": lambda args: hub_client.call_hub_endpoint("/api/messages/me", method="GET"),
    "hub_message_my_unread_count": lambda args: hub_client.call_hub_endpoint("/api/messages/me/unread-count", method="GET"),
    "hub_message_read": lambda args: hub_client.call_hub_endpoint(f"/api/messages/{args['message_id']}/read", method="POST"),
    "hub_message_stats": lambda args: hub_client.call_hub_endpoint("/api/messages/stats", method="GET"),
    "hub_message_m2m_send": lambda args: hub_client.call_hub_endpoint("/api/messages/m2m/send", method="POST", json={k: v for k, v in args.items()}),
    # --- Audit ---
    "hub_audit_logs": lambda args: hub_client.call_hub_endpoint("/api/audit/logs", method="GET"),
    "hub_audit_sessions": lambda args: hub_client.call_hub_endpoint("/api/audit/sessions/active", method="GET"),
    "hub_audit_sessions_history": lambda args: hub_client.call_hub_endpoint("/api/audit/sessions/history", method="GET"),
    "hub_audit_stats": lambda args: hub_client.call_hub_endpoint("/api/audit/stats", method="GET"),
    "hub_audit_errors": lambda args: hub_client.call_hub_endpoint("/api/audit/errors", method="GET"),
    "hub_audit_errors_stats": lambda args: hub_client.call_hub_endpoint("/api/audit/errors/stats", method="GET"),
    "hub_audit_error_detail": lambda args: hub_client.call_hub_endpoint(f"/api/audit/errors/{args['error_id']}", method="GET"),
    "hub_audit_errors_acknowledge": lambda args: hub_client.call_hub_endpoint("/api/audit/errors/acknowledge", method="POST"),
    # --- Docs ---
    "hub_docs_get": lambda args: hub_client.call_hub_endpoint(f"/api/docs/integration?section={args['section']}" if args.get('section') else "/api/docs/integration", method="GET"),
    "hub_docs_sections": lambda args: hub_client.call_hub_endpoint("/api/docs/integration/sections", method="GET"),
    "hub_changelog_get": lambda args: hub_client.call_hub_endpoint("/api/docs/changelog", method="GET"),
    "hub_changelog_diff": lambda args: hub_client.call_hub_endpoint(f"/api/docs/changelog/diff?from_version={args['from_version']}", method="GET"),
    # --- Discovery ---
    "hub_discover_services": lambda args: _handle_discover_services(args),
    "hub_call_service": lambda args: hub_client.call_discovered_service(args["service_slug"], args["endpoint"], method=args.get("method", "GET")),
    "hub_discovery_proxy": lambda args: hub_client.call_hub_endpoint("/api/discovery/proxy", method="POST", json={"app_slug": args["app_slug"], "endpoint": args["endpoint"]}),
    # --- Design ---
    "hub_design_manifest": lambda args: hub_client.call_hub_endpoint("/api/design-system/manifest", method="GET"),
    "hub_design_status": lambda args: hub_client.call_hub_endpoint("/api/admin/design-system/status", method="GET"),
    "hub_design_upload": lambda args: {"error": "Upload design system: utiliser hub_raw_call avec POST /api/admin/design-system/upload"},
    # --- Admin ---
    "hub_admin_info": lambda args: hub_client.call_hub_endpoint("/api/admin/hub-info", method="GET"),
    "hub_admin_settings": lambda args: hub_client.call_hub_endpoint("/api/admin/settings", method="GET"),
    "hub_admin_ports_status": lambda args: hub_client.call_hub_endpoint("/api/admin/ports/status", method="GET"),
    "hub_admin_dns_status": lambda args: hub_client.call_hub_endpoint("/api/admin/dns/status", method="GET"),
    "hub_pki_ca_info": lambda args: hub_client.call_hub_endpoint("/api/pki/ca/info", method="GET"),
    "hub_pki_list_certs": lambda args: hub_client.call_hub_endpoint(f"/api/pki/apps/{args['app_slug']}/certificates", method="GET"),
    "hub_pki_revoke_cert": lambda args: hub_client.call_hub_endpoint(f"/api/pki/apps/{args['app_slug']}/certificates/{args['cert_id']}/revoke", method="POST"),
}


# ============================================================
# HELPERS
# ============================================================


async def _handle_register(args):
    """Wrapper pour hub_client.register()."""
    ok = await hub_client.register()
    if ok:
        return {"success": True, "message": "Application enregistree aupres du Hub"}
    return {"success": False, "error": "Echec de l'enregistrement"}


async def _handle_get_credentials(args):
    """Lit les credentials locales sans exposer le secret."""
    if hub_client.is_registered and hub_client.credentials:
        return {
            "client_id": hub_client.credentials.client_id,
            "has_secret": bool(hub_client.credentials.client_secret),
            "has_token": hub_client.credentials.access_token is not None,
        }
    return {"error": "Application non enregistree, pas de credentials locales"}


async def _handle_regenerate_secret(args):
    """Regenere le client secret si l'app est enregistree."""
    if hub_client.is_registered:
        return await hub_client._recover_credentials()
    return {"error": "App non enregistree"}


async def _handle_get_m2m_token(args):
    token = await hub_client.get_m2m_token()
    if token:
        return {"access_token": token, "message": "Token M2M obtenu"}
    return {"error": "Impossible d'obtenir un token M2M"}


async def _handle_get_jwks(args):
    jwks = await hub_client.fetch_jwks()
    if jwks:
        return jwks
    return {"error": "Impossible de recuperer le JWKS"}


async def _handle_discover_services(args):
    services = await hub_client.discover_services()
    result = {}
    for slug, svc in services.items():
        result[slug] = {"name": svc.name, "api_url": svc.api_url, "is_healthy": svc.is_healthy}
    return result


# ============================================================
# REGISTRATION
# ============================================================

def register_all_tools(server):
    """Enregistre tous les tools et leurs handlers sur le serveur MCP."""

    @server.list_tools()
    async def list_tools() -> list[Tool]:
        return TOOLS

    @server.call_tool()
    async def call_tool(name: str, arguments: dict) -> list[TextContent]:
        handler = HANDLERS.get(name)
        if handler is None:
            return [TextContent(type="text", text=f"Tool inconnu: {name}")]

        try:
            result = await handler(arguments)
            text = json.dumps(result, indent=2, ensure_ascii=False, default=str)
        except Exception as e:
            text = json.dumps({"error": str(e), "tool": name}, indent=2)

        return [TextContent(type="text", text=text)]
