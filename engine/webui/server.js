"use strict";

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");
const { AsyncLocalStorage } = require("node:async_hooks");
const { createHash, pbkdf2Sync, randomBytes, randomUUID, timingSafeEqual } = require("node:crypto");
const { URL } = require("node:url");

const PORT = Number(process.env.PORT || process.env.SAGEWRITE_PORT || 3210);
const HOST = process.env.HOST || process.env.SAGEWRITE_HOST || "127.0.0.1";
const APP_MODE = String(process.env.SAGEWRITE_MODE || (HOST === "0.0.0.0" ? "cloud" : "local")).toLowerCase() === "cloud"
  ? "cloud"
  : "local";
const AUTH_MODE = String(process.env.SAGEWRITE_AUTH || "off").toLowerCase();
const ADMIN_PASSWORD = process.env.SAGEWRITE_ADMIN_PASSWORD || "";
const ADMIN_USER = String(process.env.SAGEWRITE_ADMIN_USER || "admin").trim() || "admin";
const ENGINE_ROOT = path.resolve(__dirname, "..");
const CLAW_ROOT = path.resolve(ENGINE_ROOT, "..", "..");
const WORKSPACE_PARENT_ROOT = process.env.SAGEWRITE_WORKSPACE_ROOT
  ? path.resolve(process.env.SAGEWRITE_WORKSPACE_ROOT)
  : CLAW_ROOT;
const USER_STORE_PATH = process.env.SAGEWRITE_USERS_FILE
  ? path.resolve(process.env.SAGEWRITE_USERS_FILE)
  : path.join(ENGINE_ROOT, "data", "users.json");
const USER_BILLING_LEDGER_PATH = process.env.SAGEWRITE_BILLING_LEDGER_FILE
  ? path.resolve(process.env.SAGEWRITE_BILLING_LEDGER_FILE)
  : path.join(path.dirname(USER_STORE_PATH), "billing-ledger.jsonl");
const USER_AUDIT_LOG_PATH = process.env.SAGEWRITE_AUDIT_LOG_FILE
  ? path.resolve(process.env.SAGEWRITE_AUDIT_LOG_FILE)
  : path.join(path.dirname(USER_STORE_PATH), "audit-log.jsonl");
const USER_WORKSPACE_ROOT = process.env.SAGEWRITE_USER_WORKSPACE_ROOT
  ? path.resolve(process.env.SAGEWRITE_USER_WORKSPACE_ROOT)
  : path.join(WORKSPACE_PARENT_ROOT, "users");
const PROJECT_METADATA_DIR = ".sagewrite";
const PROJECT_METADATA_FILE = "project.json";
const DEFAULT_TENANT_ID = normalizeTenantId(process.env.SAGEWRITE_DEFAULT_TENANT_ID || "default");
const DEFAULT_TENANT_NAME = String(process.env.SAGEWRITE_DEFAULT_TENANT_NAME || "Default Company").trim() || "Default Company";
const DEFAULT_INITIAL_CREDITS = Math.max(0, normalizeBillingNumber(process.env.SAGEWRITE_INITIAL_CREDITS, 1000));
const TOKENS_PER_CREDIT = Math.max(1, normalizeBillingNumber(process.env.SAGEWRITE_TOKENS_PER_CREDIT, 1000));
const PUBLIC_DIR = path.join(__dirname, "public");

const jobs = new Map();
const sessions = new Map();
const requestContext = new AsyncLocalStorage();
const SESSION_COOKIE = "sagewrite_session";
const SESSION_TTL_MS = 12 * 60 * 60 * 1000;
const PASSWORD_ALGORITHM = "pbkdf2-sha256";
const PASSWORD_ITERATIONS = 120_000;

function isAuthEnabled() {
  return AUTH_MODE === "password" || AUTH_MODE === "users";
}

function isUserAuthEnabled() {
  return AUTH_MODE === "users";
}

function hashValue(value) {
  return createHash("sha256").update(String(value)).digest("hex");
}

function safeEqualText(left, right) {
  const leftHash = Buffer.from(hashValue(left));
  const rightHash = Buffer.from(hashValue(right));
  return leftHash.length === rightHash.length && timingSafeEqual(leftHash, rightHash);
}

function normalizeUsername(value) {
  return String(value || "").trim().toLowerCase();
}

function normalizeBillingNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function roundBillingNumber(value) {
  return Math.round(normalizeBillingNumber(value, 0) * 1000) / 1000;
}

function normalizeTokenCount(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? Math.round(number) : 0;
}

function makeUserId(username) {
  const normalized = normalizeUsername(username);
  const readable = normalized.replace(/[^a-z0-9_-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 42);
  const suffix = createHash("sha256").update(normalized).digest("hex").slice(0, 10);
  return `${readable || "user"}-${suffix}`;
}

function normalizeTenantId(value, fallback = "default") {
  const normalized = String(value || fallback || "default")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64);
  return normalized || "default";
}

function getRoleId(role) {
  const normalized = String(role || "user").trim().toLowerCase();
  if (normalized === "admin") {
    return "platform_admin";
  }
  if (["platform_admin", "tenant_admin", "editor", "author", "viewer", "user"].includes(normalized)) {
    return normalized;
  }
  return "user";
}

function isPlatformAdmin(user) {
  return getRoleId(user?.role) === "platform_admin";
}

function canManageTenantUsers(user) {
  return ["platform_admin", "tenant_admin"].includes(getRoleId(user?.role));
}

function canManageAssignedAuthors(user) {
  return getRoleId(user?.role) === "editor";
}

function canUseUserManagement(user) {
  return canManageTenantUsers(user) || canManageAssignedAuthors(user);
}

function canManageCompanyProjects(user) {
  return ["platform_admin", "tenant_admin"].includes(getRoleId(user?.role));
}

function canAssignRole(actor, role) {
  const nextRole = getRoleId(role);
  if (isPlatformAdmin(actor)) {
    return true;
  }
  if (canManageAssignedAuthors(actor)) {
    return nextRole === "author";
  }
  return ["tenant_admin", "editor", "author", "viewer", "user"].includes(nextRole);
}

function getTenantIdFromUser(user) {
  return normalizeTenantId(user?.tenantId || DEFAULT_TENANT_ID);
}

function getRolePermissionsPublic(user) {
  const role = getRoleId(user?.role);
  const admin = role === "platform_admin" || role === "tenant_admin";
  const editor = role === "editor" || role === "user";
  const author = role === "author";
  return {
    role,
    readProject: true,
    manageTenants: role === "platform_admin",
    manageUsers: admin,
    manageAuthors: role === "editor",
    manageProjects: admin,
    viewAudit: admin,
    adjustBilling: admin,
    viewManagedAuthorBilling: admin || role === "editor",
    writeProject: admin || editor,
    writeChapters: admin || editor || author,
    runAll: admin || editor,
    runAuthoring: admin || editor || author,
    coverTools: admin || editor,
    publishTools: admin || editor,
    readOnly: role === "viewer"
  };
}

function canWriteProject(user) {
  const permissions = getRolePermissionsPublic(user);
  return permissions.writeProject;
}

function canWriteChapters(user) {
  const permissions = getRolePermissionsPublic(user);
  return permissions.writeChapters;
}

function canUseCoverTools(user) {
  const permissions = getRolePermissionsPublic(user);
  return permissions.coverTools;
}

function canUsePublishTools(user) {
  const permissions = getRolePermissionsPublic(user);
  return permissions.publishTools;
}

function canRunRoute(user, route) {
  const normalizedRoute = String(route || "").trim();
  const permissions = getRolePermissionsPublic(user);
  if (permissions.runAll) {
    return true;
  }
  if (!permissions.runAuthoring) {
    return false;
  }
  return new Set(["write", "translate", "refine-translation"]).has(normalizedRoute);
}

function hashPassword(password) {
  const salt = randomBytes(16).toString("hex");
  const hash = pbkdf2Sync(String(password), salt, PASSWORD_ITERATIONS, 32, "sha256").toString("hex");
  return {
    algorithm: PASSWORD_ALGORITHM,
    iterations: PASSWORD_ITERATIONS,
    salt,
    hash
  };
}

function verifyPassword(password, passwordRecord) {
  if (!passwordRecord || passwordRecord.algorithm !== PASSWORD_ALGORITHM) {
    return false;
  }
  const iterations = Number(passwordRecord.iterations || PASSWORD_ITERATIONS);
  const actual = pbkdf2Sync(String(password), String(passwordRecord.salt || ""), iterations, 32, "sha256");
  const expected = Buffer.from(String(passwordRecord.hash || ""), "hex");
  return expected.length === actual.length && timingSafeEqual(actual, expected);
}

function createTenantRecord({ id = DEFAULT_TENANT_ID, name = DEFAULT_TENANT_NAME, createdAt = new Date().toISOString() } = {}) {
  const tenantId = normalizeTenantId(id);
  return {
    id: tenantId,
    name: String(name || tenantId).trim() || tenantId,
    disabled: false,
    createdAt,
    updatedAt: createdAt
  };
}

function getTenantPublic(tenant) {
  if (!tenant) {
    return null;
  }
  return {
    id: normalizeTenantId(tenant.id),
    name: tenant.name || tenant.id || "",
    disabled: Boolean(tenant.disabled),
    createdAt: tenant.createdAt || "",
    updatedAt: tenant.updatedAt || tenant.createdAt || "",
    workspaceRoot: getTenantWorkspaceRoot(tenant.id)
  };
}

function normalizeUserStore(rawStore = {}) {
  const createdAt = rawStore.createdAt || new Date().toISOString();
  const tenantMap = new Map();
  const addTenant = (tenant) => {
    const record = createTenantRecord({
      id: tenant?.id || DEFAULT_TENANT_ID,
      name: tenant?.name || tenant?.displayName || DEFAULT_TENANT_NAME,
      createdAt: tenant?.createdAt || createdAt
    });
    record.disabled = Boolean(tenant?.disabled);
    record.updatedAt = tenant?.updatedAt || record.createdAt;
    tenantMap.set(record.id, record);
    return record;
  };

  addTenant({
    id: DEFAULT_TENANT_ID,
    name: DEFAULT_TENANT_NAME,
    createdAt
  });
  (Array.isArray(rawStore.tenants) ? rawStore.tenants : []).forEach(addTenant);

  const users = (Array.isArray(rawStore.users) ? rawStore.users : []).map((user) => {
    const tenantId = normalizeTenantId(user.tenantId || DEFAULT_TENANT_ID);
    if (!tenantMap.has(tenantId)) {
      addTenant({
        id: tenantId,
        name: user.tenantName || tenantId,
        createdAt: user.createdAt || createdAt
      });
    }
    return {
      ...user,
      tenantId,
      role: user.role || "user",
      managerUserId: String(user.managerUserId || "").trim()
    };
  });

  const userById = new Map(users.map((user) => [String(user.id || ""), user]));
  users.forEach((user) => {
    if (getRoleId(user.role) !== "author" || !user.managerUserId) {
      user.managerUserId = "";
      return;
    }
    const manager = userById.get(String(user.managerUserId));
    if (!manager ||
        getRoleId(manager.role) !== "editor" ||
        getTenantIdFromUser(manager) !== getTenantIdFromUser(user)) {
      user.managerUserId = "";
    }
  });

  return {
    version: Math.max(Number(rawStore.version) || 2, 3),
    createdAt,
    updatedAt: rawStore.updatedAt || rawStore.createdAt || createdAt,
    tenants: Array.from(tenantMap.values()),
    users
  };
}

function readUserStore() {
  if (!fs.existsSync(USER_STORE_PATH)) {
    return null;
  }
  const store = JSON.parse(fs.readFileSync(USER_STORE_PATH, "utf8").replace(/^\uFEFF/, ""));
  return normalizeUserStore(store);
}

function writeUserStore(store) {
  ensureDir(path.dirname(USER_STORE_PATH));
  const nextStore = normalizeUserStore({
    ...store,
    updatedAt: new Date().toISOString()
  });
  nextStore.version = 3;
  fs.writeFileSync(USER_STORE_PATH, `${JSON.stringify(nextStore, null, 2)}\n`, "utf8");
  return nextStore;
}

function ensureUserStore() {
  let store = readUserStore();
  if (store) {
    return store;
  }

  if (!ADMIN_PASSWORD) {
    return null;
  }

  const now = new Date().toISOString();
  const adminUsername = normalizeUsername(ADMIN_USER);
  store = {
    version: 3,
    createdAt: now,
    updatedAt: now,
    tenants: [createTenantRecord({
      id: DEFAULT_TENANT_ID,
      name: DEFAULT_TENANT_NAME,
      createdAt: now
    })],
    users: [{
      id: makeUserId(adminUsername),
      username: adminUsername,
      displayName: ADMIN_USER,
      role: "platform_admin",
      tenantId: DEFAULT_TENANT_ID,
      disabled: false,
      billing: createInitialBillingRecord(DEFAULT_INITIAL_CREDITS),
      password: hashPassword(ADMIN_PASSWORD),
      createdAt: now,
      updatedAt: now,
      workspaceRoot: ""
    }]
  };
  return writeUserStore(store);
}

function createInitialBillingRecord(initialCredits = DEFAULT_INITIAL_CREDITS) {
  const credits = roundBillingNumber(initialCredits);
  return {
    initialCredits: credits,
    usedTokens: 0,
    usedCredits: 0,
    balanceCredits: credits,
    updatedAt: ""
  };
}

function getUserBillingPublic(user) {
  const billing = user?.billing || {};
  const initialCredits = roundBillingNumber(Object.hasOwn(billing, "initialCredits")
    ? billing.initialCredits
    : DEFAULT_INITIAL_CREDITS);
  const usedTokens = normalizeTokenCount(billing.usedTokens);
  const usedCredits = roundBillingNumber(Object.hasOwn(billing, "usedCredits")
    ? billing.usedCredits
    : usedTokens / TOKENS_PER_CREDIT);
  return {
    initialCredits,
    usedTokens,
    usedCredits,
    balanceCredits: roundBillingNumber(initialCredits - usedCredits),
    tokensPerCredit: TOKENS_PER_CREDIT,
    updatedAt: billing.updatedAt || ""
  };
}

function getUserManagerPublic(user) {
  const managerUserId = String(user?.managerUserId || "").trim();
  if (!managerUserId) {
    return {
      managerUserId: "",
      managerUsername: "",
      managerDisplayName: "",
      managerName: ""
    };
  }
  const manager = findUserById(managerUserId);
  const managerName = manager ? (manager.displayName || manager.username || manager.id || "") : "";
  return {
    managerUserId,
    managerUsername: manager?.username || "",
    managerDisplayName: manager?.displayName || "",
    managerName
  };
}

function getUserPublic(user) {
  if (!user) {
    return null;
  }
  const tenantId = getTenantIdFromUser(user);
  const tenant = isUserAuthEnabled() ? findTenantById(tenantId) : null;
  const manager = getUserManagerPublic(user);
  return {
    id: user.id,
    username: user.username,
    displayName: user.displayName || user.username,
    role: user.role || "user",
    roleId: getRoleId(user.role),
    tenantId,
    tenantName: tenant?.name || user.tenantName || (tenantId === DEFAULT_TENANT_ID ? DEFAULT_TENANT_NAME : tenantId),
    ...manager,
    permissions: getRolePermissionsPublic(user),
    disabled: Boolean(user.disabled),
    status: user.disabled ? "disabled" : "active",
    createdAt: user.createdAt || "",
    updatedAt: user.updatedAt || user.createdAt || "",
    billing: getUserBillingPublic(user),
    workspaceRoot: getUserWorkspaceRoot(user)
  };
}

function findUserByUsername(username) {
  const store = ensureUserStore();
  if (!store) {
    return null;
  }
  const normalized = normalizeUsername(username);
  return store.users.find((user) => normalizeUsername(user.username) === normalized) || null;
}

function findUserById(userId, store = ensureUserStore()) {
  if (!store) {
    return null;
  }
  return store.users.find((user) => String(user.id || "") === String(userId || "")) || null;
}

function findTenantById(tenantId, store = ensureUserStore()) {
  if (!store) {
    return null;
  }
  const normalized = normalizeTenantId(tenantId || DEFAULT_TENANT_ID);
  return (store.tenants || []).find((tenant) => normalizeTenantId(tenant.id) === normalized) || null;
}

function ensureTenantInStore(store, { tenantId = DEFAULT_TENANT_ID, tenantName = "" } = {}) {
  const normalized = normalizeTenantId(tenantId || tenantName || DEFAULT_TENANT_ID);
  let tenant = findTenantById(normalized, store);
  const now = new Date().toISOString();
  if (!tenant) {
    tenant = createTenantRecord({
      id: normalized,
      name: tenantName || normalized,
      createdAt: now
    });
    store.tenants = Array.isArray(store.tenants) ? store.tenants : [];
    store.tenants.push(tenant);
    return tenant;
  }
  if (tenantName && tenant.name !== tenantName) {
    tenant.name = String(tenantName).trim() || tenant.name;
    tenant.updatedAt = now;
  }
  return tenant;
}

function getVisibleTenantsForUser(actor, store = ensureUserStore()) {
  if (!store) {
    return [];
  }
  if (isPlatformAdmin(actor)) {
    return (store.tenants || []).map(getTenantPublic).filter(Boolean);
  }
  const tenant = findTenantById(getTenantIdFromUser(actor), store);
  return tenant ? [getTenantPublic(tenant)] : [];
}

function canActorAccessTenant(actor, tenantId) {
  if (!isUserAuthEnabled()) {
    return true;
  }
  if (isPlatformAdmin(actor)) {
    return true;
  }
  return normalizeTenantId(tenantId) === getTenantIdFromUser(actor);
}

function getAssignableEditorsForTenant(tenantId, store = ensureUserStore()) {
  const normalizedTenantId = normalizeTenantId(tenantId || DEFAULT_TENANT_ID);
  return (store?.users || []).filter((user) =>
    getRoleId(user.role) === "editor" &&
    !user.disabled &&
    getTenantIdFromUser(user) === normalizedTenantId
  );
}

function getAssignableEditorsForActor(actor, store = ensureUserStore()) {
  if (!store || !actor) {
    return [];
  }
  if (isPlatformAdmin(actor)) {
    return (store.users || []).filter((user) => getRoleId(user.role) === "editor" && !user.disabled);
  }
  if (getRoleId(actor.role) === "tenant_admin") {
    return getAssignableEditorsForTenant(getTenantIdFromUser(actor), store);
  }
  if (canManageAssignedAuthors(actor)) {
    const actorRecord = findUserById(actor.id, store) || actor;
    return actorRecord && getRoleId(actorRecord.role) === "editor" && !actorRecord.disabled
      ? [actorRecord]
      : [];
  }
  return [];
}

function normalizeAuthorManagerUserId(managerUserId, tenantId, store = ensureUserStore()) {
  const cleanManagerUserId = String(managerUserId || "").trim();
  if (!cleanManagerUserId) {
    return "";
  }
  const manager = findUserById(cleanManagerUserId, store);
  if (!manager ||
      getRoleId(manager.role) !== "editor" ||
      manager.disabled ||
      getTenantIdFromUser(manager) !== normalizeTenantId(tenantId || DEFAULT_TENANT_ID)) {
    throw new Error("Manager editor must be an active editor in the same tenant.");
  }
  return manager.id;
}

function canActorManageUser(actor, targetUser) {
  if (!targetUser) {
    return false;
  }
  if (canManageTenantUsers(actor)) {
    if (isPlatformAdmin(targetUser) && !isPlatformAdmin(actor)) {
      return false;
    }
    return canActorAccessTenant(actor, getTenantIdFromUser(targetUser));
  }
  return canManageAssignedAuthors(actor) &&
    getRoleId(targetUser.role) === "author" &&
    String(targetUser.managerUserId || "") === String(actor?.id || "") &&
    getTenantIdFromUser(targetUser) === getTenantIdFromUser(actor);
}

function getVisibleUsersForActor(actor, store = ensureUserStore()) {
  if (!store) {
    return [];
  }
  if (isPlatformAdmin(actor)) {
    return store.users || [];
  }
  if (canManageAssignedAuthors(actor)) {
    return (store.users || []).filter((user) =>
      getTenantIdFromUser(user) === getTenantIdFromUser(actor) &&
      getRoleId(user.role) === "author" &&
      String(user.managerUserId || "") === String(actor?.id || "")
    );
  }
  const tenantId = getTenantIdFromUser(actor);
  return (store.users || []).filter((user) => getTenantIdFromUser(user) === tenantId && !isPlatformAdmin(user));
}

function getManageableUserById(actor, userId, store = ensureUserStore()) {
  const user = findUserById(userId, store);
  if (!canActorManageUser(actor, user)) {
    return null;
  }
  return user;
}

function validateUsername(username) {
  const normalized = normalizeUsername(username);
  if (!normalized) {
    throw new Error("username is required.");
  }
  if (!/^[a-z0-9][a-z0-9._-]{1,62}[a-z0-9]$/.test(normalized)) {
    throw new Error("username must be 3-64 chars and use letters, numbers, dot, underscore, or hyphen.");
  }
  return normalized;
}

function createUserAccount({ username, password, displayName = "", role = "user", initialCredits = DEFAULT_INITIAL_CREDITS, tenantId = "", tenantName = "", managerUserId = "", actor = null }) {
  const normalized = validateUsername(username);
  if (!password || String(password).length < 8) {
    throw new Error("password must be at least 8 characters.");
  }
  const currentActor = actor || getCurrentUserContext();
  if (!canUseUserManagement(currentActor)) {
    throw new Error("User management permission is required.");
  }
  const nextRole = canManageAssignedAuthors(currentActor) ? "author" : getRoleId(role);
  if (!canAssignRole(currentActor, nextRole)) {
    throw new Error("You cannot assign that role.");
  }
  const nextInitialCredits = canManageTenantUsers(currentActor)
    ? roundBillingNumber(initialCredits)
    : DEFAULT_INITIAL_CREDITS;
  if (nextInitialCredits < 0) {
    throw new Error("initialCredits cannot be negative.");
  }
  const store = ensureUserStore() || {
    version: 3,
    createdAt: new Date().toISOString(),
    tenants: [],
    users: []
  };
  if (store.users.some((user) => normalizeUsername(user.username) === normalized)) {
    throw new Error("username already exists.");
  }
  const targetTenantId = isPlatformAdmin(currentActor)
    ? normalizeTenantId(tenantId || tenantName || getTenantIdFromUser(currentActor))
    : getTenantIdFromUser(currentActor);
  if (!isPlatformAdmin(currentActor) && !canManageAssignedAuthors(currentActor) && tenantId && normalizeTenantId(tenantId) !== targetTenantId) {
    throw new Error("You can only create users in your own tenant.");
  }
  const targetTenant = ensureTenantInStore(store, {
    tenantId: targetTenantId,
    tenantName: isPlatformAdmin(currentActor) ? tenantName : ""
  });
  const nextManagerUserId = nextRole === "author"
    ? (canManageAssignedAuthors(currentActor)
      ? currentActor.id
      : normalizeAuthorManagerUserId(managerUserId, targetTenant.id, store))
    : "";
  const now = new Date().toISOString();
  const user = {
    id: makeUserId(normalized),
    username: normalized,
    displayName: String(displayName || username).trim() || normalized,
    role: nextRole,
    tenantId: targetTenant.id,
    managerUserId: nextManagerUserId,
    disabled: false,
    billing: createInitialBillingRecord(nextInitialCredits),
    password: hashPassword(password),
    createdAt: now,
    updatedAt: now,
    workspaceRoot: ""
  };
  store.users.push(user);
  writeUserStore(store);
  ensureDir(getUserWorkspaceRoot(user));
  return getUserPublic(user);
}

function countActivePlatformAdmins(store) {
  return (store?.users || []).filter((user) => isPlatformAdmin(user) && !user.disabled).length;
}

function assertActiveAdminRemains(store, user, nextRole, nextDisabled) {
  const wasActivePlatformAdmin = isPlatformAdmin(user) && !user.disabled;
  const willBeActivePlatformAdmin = getRoleId(nextRole) === "platform_admin" && !nextDisabled;
  if (wasActivePlatformAdmin && !willBeActivePlatformAdmin && countActivePlatformAdmins(store) <= 1) {
    throw new Error("At least one active platform admin is required.");
  }
}

function updateUserAccount(userId, updates = {}, actor = getCurrentUserContext()) {
  const store = ensureUserStore();
  if (!store) {
    throw new Error("User store is not initialized.");
  }
  const user = getManageableUserById(actor, userId, store);
  if (!user) {
    throw new Error("User not found.");
  }

  const actorManagesAssignedAuthors = canManageAssignedAuthors(actor);
  const nextRole = Object.hasOwn(updates, "role")
    ? getRoleId(updates.role || "user")
    : (user.role || "user");
  if (actorManagesAssignedAuthors && nextRole !== "author") {
    throw new Error("Editors can only manage author accounts.");
  }
  if (!canAssignRole(actor, nextRole)) {
    throw new Error("You cannot assign that role.");
  }
  if (actorManagesAssignedAuthors && (Object.hasOwn(updates, "tenantId") || Object.hasOwn(updates, "managerUserId"))) {
    throw new Error("Editors cannot move authors between tenants or editors.");
  }

  const nextDisabled = Object.hasOwn(updates, "disabled")
    ? Boolean(updates.disabled)
    : Boolean(user.disabled);

  assertActiveAdminRemains(store, user, nextRole, nextDisabled);

  let nextTenantId = getTenantIdFromUser(user);
  if (Object.hasOwn(updates, "tenantId") && isPlatformAdmin(actor)) {
    const nextTenant = ensureTenantInStore(store, {
      tenantId: updates.tenantId,
      tenantName: updates.tenantName || ""
    });
    nextTenantId = nextTenant.id;
  }
  const currentTenantId = getTenantIdFromUser(user);
  const requestedManagerUserId = Object.hasOwn(updates, "managerUserId")
    ? updates.managerUserId
    : (nextTenantId === currentTenantId ? user.managerUserId : "");
  const nextManagerUserId = nextRole === "author"
    ? (actorManagesAssignedAuthors
      ? actor.id
      : normalizeAuthorManagerUserId(
        requestedManagerUserId,
        nextTenantId,
        store
      ))
    : "";

  user.role = nextRole;
  user.disabled = nextDisabled;
  user.tenantId = nextTenantId;
  user.managerUserId = nextManagerUserId;
  user.updatedAt = new Date().toISOString();
  writeUserStore(store);
  return getUserPublic(user);
}

function resetUserPassword(userId, password, actor = getCurrentUserContext()) {
  if (!password || String(password).length < 8) {
    throw new Error("password must be at least 8 characters.");
  }
  const store = ensureUserStore();
  if (!store) {
    throw new Error("User store is not initialized.");
  }
  const user = getManageableUserById(actor, userId, store);
  if (!user) {
    throw new Error("User not found.");
  }
  user.password = hashPassword(password);
  user.passwordUpdatedAt = new Date().toISOString();
  user.updatedAt = user.passwordUpdatedAt;
  writeUserStore(store);
  return getUserPublic(user);
}

function changeOwnPassword(userId, currentPassword, newPassword) {
  if (!newPassword || String(newPassword).length < 8) {
    throw new Error("new password must be at least 8 characters.");
  }
  const store = ensureUserStore();
  if (!store) {
    throw new Error("User store is not initialized.");
  }
  const user = findUserById(userId, store);
  if (!user || user.disabled) {
    throw new Error("User not found.");
  }
  if (!verifyPassword(currentPassword || "", user.password)) {
    throw new Error("Current password is incorrect.");
  }
  user.password = hashPassword(newPassword);
  user.passwordUpdatedAt = new Date().toISOString();
  user.updatedAt = user.passwordUpdatedAt;
  writeUserStore(store);
  return getUserPublic(user);
}

function getBillingConfigPublic({ includePrivatePaths = canCurrentUserSeeServerPaths() } = {}) {
  return {
    enabled: isUserAuthEnabled(),
    defaultInitialCredits: DEFAULT_INITIAL_CREDITS,
    tokensPerCredit: TOKENS_PER_CREDIT,
    ledgerPath: isUserAuthEnabled() && includePrivatePaths ? USER_BILLING_LEDGER_PATH : ""
  };
}

function normalizeUsageObject(usage) {
  if (!usage || typeof usage !== "object") {
    return null;
  }
  const inputTokens = normalizeTokenCount(usage.input_tokens ?? usage.prompt_tokens ?? usage.inputTokens);
  const outputTokens = normalizeTokenCount(usage.output_tokens ?? usage.completion_tokens ?? usage.outputTokens);
  const totalTokens = normalizeTokenCount(usage.total_tokens ?? usage.totalTokens) || inputTokens + outputTokens;
  if (!totalTokens) {
    return null;
  }
  const cachedTokens = normalizeTokenCount(
    usage.cached_tokens ??
    usage.cachedTokens ??
    usage.input_tokens_details?.cached_tokens ??
    usage.prompt_tokens_details?.cached_tokens
  );
  return {
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    total_tokens: totalTokens,
    cached_tokens: cachedTokens
  };
}

function extractTokenUsageFromText(text) {
  const source = String(text || "");
  const totalLineMatches = Array.from(source.matchAll(/Token usage total:\s*input=(\d+)\s*,?\s*output=(\d+)\s*,?\s*total=(\d+)/gi));
  const usageMatches = Array.from(source.matchAll(/Token usage:\s*input=(\d+)\s*,?\s*output=(\d+)\s*,?\s*total=(\d+)/gi));
  const match = totalLineMatches.at(-1) || usageMatches.at(-1);
  if (!match) {
    return null;
  }
  return normalizeUsageObject({
    input_tokens: match[1],
    output_tokens: match[2],
    total_tokens: match[3]
  });
}

function parseLocalTimestamp(value) {
  if (!value) {
    return null;
  }
  const match = String(value).match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})/);
  if (!match) {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return new Date(
    Number(match[1]),
    Number(match[2]) - 1,
    Number(match[3]),
    Number(match[4]),
    Number(match[5]),
    Number(match[6])
  );
}

function extractTokenUsageFromRunHistory(job) {
  const bookName = job.meta?.bookName;
  if (!bookName) {
    return null;
  }
  const paths = getWorkspacePaths(bookName, job.meta?.workspaceParentRoot || getWorkspaceParentRoot());
  const runLogPath = path.join(paths.logRoot, "run_history.jsonl");
  if (!fs.existsSync(runLogPath)) {
    return null;
  }
  const startedAt = new Date(job.createdAt).getTime() - 10_000;
  const route = String(job.meta?.route || "");
  const routeStepAliases = {
    "refine-translation": "refine_translation"
  };
  const expectedStep = routeStepAliases[route] || route;
  const lines = fs.readFileSync(runLogPath, "utf8").split(/\r?\n/).filter(Boolean).slice(-200);
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    try {
      const entry = JSON.parse(lines[index]);
      const entryDate = parseLocalTimestamp(entry.timestamp);
      if (entryDate && entryDate.getTime() < startedAt) {
        continue;
      }
      if (expectedStep && entry.step && entry.step !== expectedStep) {
        continue;
      }
      const data = entry.data || {};
      const usage = normalizeUsageObject({
        input_tokens: data.input_tokens_total ?? data.input_tokens,
        output_tokens: data.output_tokens_total ?? data.output_tokens,
        total_tokens: data.total_tokens_total ?? data.total_tokens
      });
      if (usage) {
        return usage;
      }
    } catch {
      continue;
    }
  }
  return null;
}

function recordUserTokenUsage(userId, details = {}) {
  if (!isUserAuthEnabled() || !userId) {
    return null;
  }
  const usage = normalizeUsageObject(details.usage);
  if (!usage) {
    return null;
  }
  const store = ensureUserStore();
  if (!store) {
    return null;
  }
  const user = findUserById(userId, store);
  if (!user) {
    return null;
  }

  const currentBilling = getUserBillingPublic(user);
  const usedTokens = currentBilling.usedTokens + usage.total_tokens;
  const chargedCredits = roundBillingNumber(usage.total_tokens / TOKENS_PER_CREDIT);
  const usedCredits = roundBillingNumber(currentBilling.usedCredits + chargedCredits);
  const now = new Date().toISOString();
  user.billing = {
    initialCredits: currentBilling.initialCredits,
    usedTokens,
    usedCredits,
    balanceCredits: roundBillingNumber(currentBilling.initialCredits - usedCredits),
    updatedAt: now
  };
  user.updatedAt = now;
  writeUserStore(store);

  const event = {
    id: randomUUID(),
    createdAt: now,
    userId: user.id,
    username: user.username,
    tenantId: getTenantIdFromUser(user),
    source: details.source || "unknown",
    route: details.route || "",
    jobId: details.jobId || "",
    bookName: details.bookName || "",
    model: details.model || "",
    usage,
    chargedCredits,
    balanceCredits: user.billing.balanceCredits,
    tokensPerCredit: TOKENS_PER_CREDIT
  };
  appendJsonLine(USER_BILLING_LEDGER_PATH, event);
  return {
    event,
    billing: getUserBillingPublic(user)
  };
}

function recordUserBillingAdjustment(userId, { creditDelta, note = "", adminUser = null } = {}) {
  if (!isUserAuthEnabled()) {
    throw new Error("User account mode is not enabled.");
  }
  const rawDelta = Number(creditDelta);
  if (!Number.isFinite(rawDelta)) {
    throw new Error("creditDelta must be a number.");
  }
  const nextCreditDelta = roundBillingNumber(rawDelta);
  if (nextCreditDelta === 0) {
    throw new Error("creditDelta cannot be zero.");
  }
  if (Math.abs(nextCreditDelta) > 1_000_000) {
    throw new Error("creditDelta is too large.");
  }
  const cleanNote = String(note || "").replace(/\s+/g, " ").trim();
  if (cleanNote.length > 500) {
    throw new Error("note must be 500 characters or fewer.");
  }

  const store = ensureUserStore();
  if (!store) {
    throw new Error("User store is not initialized.");
  }
  const user = findUserById(userId, store);
  if (!user) {
    throw new Error("User not found.");
  }

  const currentBilling = getUserBillingPublic(user);
  const now = new Date().toISOString();
  const initialCredits = roundBillingNumber(currentBilling.initialCredits + nextCreditDelta);
  user.billing = {
    initialCredits,
    usedTokens: currentBilling.usedTokens,
    usedCredits: currentBilling.usedCredits,
    balanceCredits: roundBillingNumber(initialCredits - currentBilling.usedCredits),
    updatedAt: now
  };
  user.updatedAt = now;
  writeUserStore(store);

  const event = {
    id: randomUUID(),
    eventType: "credit_adjustment",
    createdAt: now,
    userId: user.id,
    username: user.username,
    tenantId: getTenantIdFromUser(user),
    source: "admin_credit_adjustment",
    route: "admin-billing",
    usage: {
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0,
      cached_tokens: 0
    },
    chargedCredits: 0,
    creditDelta: nextCreditDelta,
    balanceCredits: user.billing.balanceCredits,
    initialCredits,
    usedCredits: user.billing.usedCredits,
    tokensPerCredit: TOKENS_PER_CREDIT,
    note: cleanNote,
    adminUserId: adminUser?.id || "",
    adminUsername: adminUser?.username || adminUser?.displayName || ""
  };
  appendJsonLine(USER_BILLING_LEDGER_PATH, event);
  return {
    event,
    user: getUserPublic(user),
    billing: getUserBillingPublic(user)
  };
}

function getUserBillingEvents(userId, limit = 20) {
  if (!isUserAuthEnabled() || !userId) {
    return [];
  }
  const safeLimit = Math.min(100, Math.max(1, Math.round(Number(limit) || 20)));
  return readJsonLines(USER_BILLING_LEDGER_PATH)
    .filter((event) => event?.userId === userId)
    .slice(-safeLimit)
    .reverse()
    .map((event) => ({
      id: event.id || "",
      createdAt: event.createdAt || "",
      source: event.source || "",
      tenantId: event.tenantId || "",
      route: event.route || "",
      jobId: event.jobId || "",
      bookName: event.bookName || "",
      model: event.model || "",
      eventType: event.eventType || (event.source === "admin_credit_adjustment" ? "credit_adjustment" : "token_usage"),
      usage: normalizeUsageObject(event.usage) || {
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0,
        cached_tokens: 0
      },
      chargedCredits: roundBillingNumber(event.chargedCredits),
      creditDelta: roundBillingNumber(event.creditDelta),
      balanceCredits: roundBillingNumber(event.balanceCredits),
      initialCredits: roundBillingNumber(event.initialCredits),
      usedCredits: roundBillingNumber(event.usedCredits),
      tokensPerCredit: normalizeBillingNumber(event.tokensPerCredit, TOKENS_PER_CREDIT),
      note: event.note || "",
      adminUsername: event.adminUsername || "",
      adminUserId: event.adminUserId || ""
    }));
}

function recordJobTokenUsage(job) {
  if (!job || job.billingRecorded) {
    return null;
  }
  job.billingRecorded = true;
  const usage = extractTokenUsageFromText(job.output) || extractTokenUsageFromRunHistory(job);
  if (!usage) {
    return null;
  }
  return recordUserTokenUsage(job.meta?.userId, {
    usage,
    source: "powershell_job",
    route: job.meta?.route || "",
    jobId: job.id,
    bookName: job.meta?.bookName || ""
  });
}

function getLegacyUserContext(mode = "local") {
  return {
    id: mode === "password" ? "admin" : "single-user",
    username: mode === "password" ? "admin" : "single-user",
    displayName: mode === "password" ? "Admin" : "Single User",
    role: "platform_admin",
    roleId: "platform_admin",
    tenantId: DEFAULT_TENANT_ID,
    tenantName: DEFAULT_TENANT_NAME,
    authMode: mode,
    workspaceRoot: WORKSPACE_PARENT_ROOT,
    legacy: true
  };
}

function getTenantWorkspaceRoot(tenantId = DEFAULT_TENANT_ID) {
  return path.join(USER_WORKSPACE_ROOT, normalizeTenantId(tenantId));
}

function getUserWorkspaceRoot(user) {
  if (!isUserAuthEnabled()) {
    return WORKSPACE_PARENT_ROOT;
  }
  if (user?.workspaceRoot && path.isAbsolute(user.workspaceRoot)) {
    return path.resolve(user.workspaceRoot);
  }
  return getTenantWorkspaceRoot(getTenantIdFromUser(user));
}

function getCurrentUserContext() {
  const store = requestContext.getStore();
  if (store?.user) {
    return store.user;
  }
  if (AUTH_MODE === "password") {
    return getLegacyUserContext("password");
  }
  return getLegacyUserContext("local");
}

function getWorkspaceParentRoot() {
  const currentUser = getCurrentUserContext();
  if (isUserAuthEnabled() && isPlatformAdmin(currentUser)) {
    return WORKSPACE_PARENT_ROOT;
  }
  return currentUser.workspaceRoot || WORKSPACE_PARENT_ROOT;
}

function getAuthDetails() {
  return {
    authMode: AUTH_MODE,
    authEnabled: isAuthEnabled(),
    userAuthEnabled: isUserAuthEnabled(),
    userStorePath: isUserAuthEnabled() ? USER_STORE_PATH : "",
    userWorkspaceRoot: isUserAuthEnabled() ? USER_WORKSPACE_ROOT : "",
    auditLogPath: isUserAuthEnabled() ? USER_AUDIT_LOG_PATH : "",
    billing: getBillingConfigPublic()
  };
}

function getPublicAuthDetails() {
  return {
    authMode: AUTH_MODE,
    authEnabled: isAuthEnabled(),
    userAuthEnabled: isUserAuthEnabled(),
    billing: {
      enabled: isUserAuthEnabled(),
      defaultInitialCredits: DEFAULT_INITIAL_CREDITS,
      tokensPerCredit: TOKENS_PER_CREDIT
    }
  };
}

function canCurrentUserSeeServerPaths() {
  if (!isUserAuthEnabled()) {
    return true;
  }
  return isPlatformAdmin(getCurrentUserContext());
}

function assertCurrentUserIsAdmin() {
  const user = getCurrentUserContext();
  if (!user || !canManageTenantUsers(user)) {
    throw new Error("Admin permission is required.");
  }
  return user;
}

function assertCurrentUserCanUseUserManagement() {
  const user = getCurrentUserContext();
  if (!user || !canUseUserManagement(user)) {
    throw new Error("User management permission is required.");
  }
  return user;
}

function getPermissionErrorStatus(error, fallback = 400) {
  return /permission is required/i.test(error?.message || "") ? 403 : fallback;
}

function parseCookies(req) {
  const header = req.headers.cookie || "";
  return Object.fromEntries(header.split(";").map((part) => {
    const [name, ...rest] = part.trim().split("=");
    return [name, decodeURIComponent(rest.join("=") || "")];
  }).filter(([name]) => name));
}

function createSession(user) {
  const token = randomBytes(32).toString("hex");
  const publicUser = getUserPublic(user);
  sessions.set(token, {
    createdAt: Date.now(),
    expiresAt: Date.now() + SESSION_TTL_MS,
    user: publicUser ? {
      ...publicUser,
      authMode: AUTH_MODE,
      workspaceRoot: user?.workspaceRoot || publicUser.workspaceRoot
    } : null
  });
  return token;
}

function cleanupSessions() {
  const now = Date.now();
  for (const [token, session] of sessions.entries()) {
    if (!session || session.expiresAt <= now) {
      sessions.delete(token);
    }
  }
}

function deleteSessionsForUser(userId, exceptToken = "") {
  for (const [token, session] of sessions.entries()) {
    if (token !== exceptToken && session?.user?.id === userId) {
      sessions.delete(token);
    }
  }
}

function getValidSession(req) {
  if (!isAuthEnabled()) {
    return null;
  }
  cleanupSessions();
  const token = parseCookies(req)[SESSION_COOKIE];
  const session = token ? sessions.get(token) : null;
  if (!session || session.expiresAt <= Date.now()) {
    return null;
  }
  session.expiresAt = Date.now() + SESSION_TTL_MS;
  return { token, session };
}

function getAuthenticatedUserFromRequest(req) {
  if (!isAuthEnabled()) {
    return getLegacyUserContext("local");
  }
  const valid = getValidSession(req);
  if (valid?.session?.user) {
    if (isUserAuthEnabled()) {
      const user = findUserById(valid.session.user.id) || findUserByUsername(valid.session.user.username);
      if (!user || user.disabled) {
        sessions.delete(valid.token);
        return null;
      }
      const refreshedUser = {
        ...getUserPublic(user),
        authMode: AUTH_MODE
      };
      valid.session.user = refreshedUser;
      return refreshedUser;
    }
    return valid.session.user;
  }
  return null;
}

function isLoginRequest(method, pathname) {
  return pathname === "/login.html" ||
    pathname === "/api/auth/status" ||
    (method === "POST" && pathname === "/api/auth/login");
}

function redirectToLogin(res) {
  res.writeHead(302, {
    "Location": "/login.html",
    "Cache-Control": "no-store"
  });
  res.end();
}

function requireAuth(req, res, url) {
  if (!isAuthEnabled()) {
    req.sagewriteUser = getLegacyUserContext("local");
    return true;
  }
  if (isLoginRequest(req.method, url.pathname)) {
    return true;
  }
  const user = getAuthenticatedUserFromRequest(req);
  if (user) {
    req.sagewriteUser = user;
    return true;
  }
  if (url.pathname.startsWith("/api/")) {
    sendJson(res, 401, { error: "Authentication required.", authRequired: true });
  } else {
    redirectToLogin(res);
  }
  return false;
}

function denyRoleAccess(req, res, action, details = {}) {
  recordAuditEvent("permission.denied", {
    req,
    actor: getCurrentUserContext(),
    status: "failed",
    route: details.route || "",
    bookName: details.bookName || "",
    jobId: details.jobId || "",
    message: details.message || `Permission denied for ${action}.`,
    data: {
      action,
      pathname: details.pathname || "",
      method: details.method || ""
    }
  });
  sendJson(res, 403, { error: details.message || "当前角色没有权限执行这个操作。" });
  return false;
}

function getRequiredProjectPermission(method, pathname) {
  if (!isUserAuthEnabled() || method === "GET") {
    return null;
  }
  if (pathname === "/api/account/password" || pathname === "/api/auth/logout") {
    return null;
  }
  if (pathname === "/api/users" ||
      pathname === "/api/projects" ||
      pathname === "/api/admin/audit" ||
      /^\/api\/users\/[^/]+(?:\/password|\/billing|\/billing-adjustment)?$/.test(pathname)) {
    return null;
  }
  if (/^\/api\/jobs\/[^/]+\/cancel$/.test(pathname)) {
    return "cancel_job";
  }
  if (pathname.startsWith("/api/run/")) {
    return "run_route";
  }

  const readLikePostPaths = new Set([
    "/api/open-output",
    "/api/open-output-folder",
    "/api/reveal-output",
    "/api/open-publish-folder",
    "/api/reveal-publish-file",
    "/api/open-publish-file",
    "/api/open-cover-folder",
    "/api/reveal-cover-file"
  ]);
  if (readLikePostPaths.has(pathname)) {
    return null;
  }

  if (pathname === "/api/chapter") {
    return "write_chapters";
  }

  const projectWritePaths = new Set([
    "/api/objective-md",
    "/api/toc",
    "/api/frontmatter"
  ]);
  if (projectWritePaths.has(pathname)) {
    return "write_project";
  }

  const publishWritePaths = new Set([
    "/api/publish-metadata",
    "/api/amazon-description",
    "/api/generate-kobo-account-md"
  ]);
  if (publishWritePaths.has(pathname)) {
    return "publish_tools";
  }

  const coverWritePaths = new Set([
    "/api/kdp-acceptance-existing-file",
    "/api/kdp-acceptance",
    "/api/kdp-acceptance-png",
    "/api/kdp-llm-text-regions",
    "/api/kdp-fix-report",
    "/api/kdp-fix-workbench/prepare",
    "/api/kdp-img-black/crop",
    "/api/kdp-img-black/resize",
    "/api/kdp-img-black/state",
    "/api/kdp-img-black/fill",
    "/api/kdp-img-black/composite",
    "/api/kdp-img-black/png-to-pdf",
    "/api/cover-midjourney-prompt",
    "/api/cover-workbench-state",
    "/api/cover-midjourney-prompt/save",
    "/api/cover-base-image/import",
    "/api/cover-copy"
  ]);
  if (coverWritePaths.has(pathname)) {
    return "cover_tools";
  }

  if (method === "POST" || method === "PATCH" || method === "DELETE") {
    return "write_project";
  }
  return null;
}

function authorizeProjectApiRequest(req, res, url) {
  const required = getRequiredProjectPermission(req.method, url.pathname);
  if (!required) {
    return true;
  }
  const user = getCurrentUserContext();
  if (required === "write_chapters" && canWriteChapters(user)) {
    return true;
  }
  if (required === "write_project" && canWriteProject(user)) {
    return true;
  }
  if (required === "cover_tools" && canUseCoverTools(user)) {
    return true;
  }
  if (required === "publish_tools" && canUsePublishTools(user)) {
    return true;
  }
  if (required === "run_route") {
    const route = url.pathname.split("/").pop();
    if (canRunRoute(user, route)) {
      return true;
    }
    return denyRoleAccess(req, res, required, {
      pathname: url.pathname,
      method: req.method,
      route,
      message: `当前角色不能运行 ${route}。`
    });
  }
  if (required === "cancel_job") {
    return true;
  }
  return denyRoleAccess(req, res, required, {
    pathname: url.pathname,
    method: req.method
  });
}

function isCloudMode() {
  return APP_MODE === "cloud";
}

function assertLocalOpenAllowed() {
  if (isCloudMode()) {
    throw new Error("Cloud mode cannot open server desktop files or folders. Use a download/preview endpoint instead.");
  }
}

function getChildProcessEnv(workspaceParentRoot = getWorkspaceParentRoot()) {
  const currentUser = getCurrentUserContext();
  return {
    ...process.env,
    SAGEWRITE_MODE: APP_MODE,
    SAGEWRITE_HOST: HOST,
    SAGEWRITE_PORT: String(PORT),
    SAGEWRITE_WORKSPACE_ROOT: path.resolve(workspaceParentRoot || getWorkspaceParentRoot()),
    SAGEWRITE_USER_ID: currentUser.id || "",
    SAGEWRITE_USERNAME: currentUser.username || "",
    SAGEWRITE_TENANT_ID: getTenantIdFromUser(currentUser),
    SAGEWRITE_TENANT_NAME: currentUser.tenantName || ""
  };
}

function getWorkspacePaths(bookName, workspaceParentRoot = getWorkspaceParentRoot(), options = {}) {
  if (workspaceParentRoot && typeof workspaceParentRoot === "object") {
    options = workspaceParentRoot;
    workspaceParentRoot = options.workspaceParentRoot || getWorkspaceParentRoot();
  }
  const workspacePath = path.join(workspaceParentRoot, `workspace-${bookName}`);
  const bookRoot = path.join(workspacePath, "sagewrite", "book");
  const logRoot = path.join(bookRoot, "logs");
  const outputRoot = path.join(bookRoot, "04_output");
  const coverRoot = resolveCoverRoot(bookRoot, "ebook");
  const coverBriefRoot = path.join(coverRoot, "brief");
  const coverDraftRoot = path.join(coverRoot, "drafts");
  const coverReviewRoot = path.join(coverRoot, "reviews");
  const coverLayoutRoot = path.join(coverRoot, "layout");
  const coverMockupRoot = path.join(coverRoot, "mockup");
  const coverFinalRoot = path.join(coverRoot, "final");
  const coverCopyJsonPath = path.join(coverBriefRoot, "cover_copy.json");
  const coverCopyMdPath = path.join(coverBriefRoot, "cover_copy.md");
  const coverAssistantJsonPath = path.join(coverBriefRoot, "cover_assistant_last.json");
  const coverAssistantMdPath = path.join(coverBriefRoot, "cover_assistant_last.md");
  const frontmatterBaseRoot = path.join(bookRoot, "00_frontmatter");
  const frontmatterRoot = path.join(frontmatterBaseRoot, "ebook");
  const frontmatterManifestPath = path.join(frontmatterRoot, "frontmatter_manifest.json");
  const coverPagePath = path.join(frontmatterRoot, "cover_page.md");
  const titlePagePath = path.join(frontmatterRoot, "title_page.md");
  const copyrightPagePath = path.join(frontmatterRoot, "copyright_page.md");
  const webRunRoot = path.join(logRoot, "webui-runs");
  const webRunIndexPath = path.join(logRoot, "webui_runs.jsonl");
  const webJobRoot = path.join(logRoot, "webui-jobs");

  const paths = {
    workspacePath,
    bookRoot,
    logRoot,
    outputRoot,
    coverRoot,
    coverBriefRoot,
    coverDraftRoot,
    coverReviewRoot,
    coverLayoutRoot,
    coverMockupRoot,
    coverFinalRoot,
    coverCopyJsonPath,
    coverCopyMdPath,
    coverAssistantJsonPath,
    coverAssistantMdPath,
    frontmatterBaseRoot,
    frontmatterRoot,
    frontmatterManifestPath,
    coverPagePath,
    titlePagePath,
    copyrightPagePath,
    webRunRoot,
    webRunIndexPath,
    webJobRoot
  };
  if (!options.skipProjectAccessCheck) {
    assertCurrentUserCanAccessProjectPaths(bookName, paths);
  }
  return paths;
}

function hasCoverArtifactsAt(root) {
  if (!fs.existsSync(root)) {
    return false;
  }

  const checks = [
    path.join(root, "brief", "cover_brief.json"),
    path.join(root, "brief", "cover_strategy.json"),
    path.join(root, "brief", "cover_copy.json"),
    path.join(root, "drafts"),
    path.join(root, "layout"),
    path.join(root, "mockup"),
    path.join(root, "final")
  ];

  return checks.some((item) => fs.existsSync(item));
}

function resolveCoverRoot(bookRoot, edition = "ebook") {
  const baseRoot = path.join(bookRoot, "07_cover");
  const editionRoot = path.join(baseRoot, edition);

  if (hasCoverArtifactsAt(editionRoot)) {
    return editionRoot;
  }

  if (edition === "ebook" && hasCoverArtifactsAt(baseRoot)) {
    return baseRoot;
  }

  return editionRoot;
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function isPathInside(rootPath, targetPath) {
  const rootResolved = path.resolve(rootPath);
  const targetResolved = path.resolve(targetPath);
  const rootCompare = process.platform === "win32" ? rootResolved.toLowerCase() : rootResolved;
  const targetCompare = process.platform === "win32" ? targetResolved.toLowerCase() : targetResolved;
  if (targetCompare === rootCompare) {
    return true;
  }
  const rootWithSep = rootCompare.endsWith(path.sep) ? rootCompare : `${rootCompare}${path.sep}`;
  return targetCompare.startsWith(rootWithSep);
}

function resolveInside(rootPath, ...segments) {
  const targetPath = path.resolve(rootPath, ...segments);
  if (!isPathInside(rootPath, targetPath)) {
    throw new Error("Resolved path is outside the allowed directory.");
  }
  return targetPath;
}

function getProjectMetadataPath(bookRoot) {
  return path.join(bookRoot, PROJECT_METADATA_DIR, PROJECT_METADATA_FILE);
}

function getWorkspaceParentRootFromPaths(paths) {
  return path.dirname(path.resolve(paths.workspacePath));
}

function inferTenantIdFromWorkspaceParentRoot(workspaceParentRoot) {
  if (!isUserAuthEnabled()) {
    return DEFAULT_TENANT_ID;
  }
  const root = path.resolve(workspaceParentRoot || getWorkspaceParentRoot());
  const userRoot = path.resolve(USER_WORKSPACE_ROOT);
  const relative = path.relative(userRoot, root);
  if (relative && relative !== "." && !relative.startsWith("..") && !path.isAbsolute(relative)) {
    const [tenantSegment] = relative.split(path.sep);
    if (tenantSegment) {
      return normalizeTenantId(tenantSegment, DEFAULT_TENANT_ID);
    }
  }
  return getTenantIdFromUser(getCurrentUserContext());
}

function getProjectTenantName(tenantId) {
  const tenant = isUserAuthEnabled() ? findTenantById(tenantId) : null;
  return tenant?.name || (tenantId === DEFAULT_TENANT_ID ? DEFAULT_TENANT_NAME : tenantId);
}

function readProjectMetadataFile(bookRoot) {
  const metadataPath = getProjectMetadataPath(bookRoot);
  if (!fs.existsSync(metadataPath)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(metadataPath, "utf8").replace(/^\uFEFF/, ""));
  } catch {
    return null;
  }
}

function normalizeProjectMetadata(rawMetadata, { bookName, paths, explicit = false } = {}) {
  const workspaceParentRoot = paths ? getWorkspaceParentRootFromPaths(paths) : getWorkspaceParentRoot();
  const tenantId = normalizeTenantId(rawMetadata?.tenantId || inferTenantIdFromWorkspaceParentRoot(workspaceParentRoot), DEFAULT_TENANT_ID);
  const tenantName = String(rawMetadata?.tenantName || getProjectTenantName(tenantId)).trim() || tenantId;
  const createdAt = rawMetadata?.createdAt || new Date().toISOString();
  const hasExplicitOwner = Boolean(
    rawMetadata?.ownerUserId ||
    rawMetadata?.authorUserId ||
    rawMetadata?.editorUserId ||
    rawMetadata?.createdByUserId
  );
  return {
    version: Math.max(Number(rawMetadata?.version) || 1, 1),
    bookName: String(rawMetadata?.bookName || bookName || "").trim(),
    tenantId,
    tenantName,
    ownerUserId: String(rawMetadata?.ownerUserId || "").trim(),
    ownerUsername: String(rawMetadata?.ownerUsername || "").trim(),
    ownerDisplayName: String(rawMetadata?.ownerDisplayName || "").trim(),
    authorUserId: String(rawMetadata?.authorUserId || "").trim(),
    authorUsername: String(rawMetadata?.authorUsername || "").trim(),
    editorUserId: String(rawMetadata?.editorUserId || "").trim(),
    editorUsername: String(rawMetadata?.editorUsername || "").trim(),
    createdByUserId: String(rawMetadata?.createdByUserId || rawMetadata?.ownerUserId || "").trim(),
    createdByUsername: String(rawMetadata?.createdByUsername || rawMetadata?.ownerUsername || "").trim(),
    createdAt,
    updatedAt: rawMetadata?.updatedAt || createdAt,
    explicitOwnership: Boolean(explicit && hasExplicitOwner),
    legacyImported: Boolean(rawMetadata?.legacyImported || !explicit || !hasExplicitOwner),
    metadataPath: paths ? getProjectMetadataPath(paths.bookRoot) : ""
  };
}

function getProjectMetadataForPaths(bookName, paths) {
  const rawMetadata = readProjectMetadataFile(paths.bookRoot);
  return normalizeProjectMetadata(rawMetadata || {}, {
    bookName,
    paths,
    explicit: Boolean(rawMetadata)
  });
}

function getManagedAuthorIdsForEditor(editorUser) {
  if (!canManageAssignedAuthors(editorUser)) {
    return new Set();
  }
  const store = ensureUserStore();
  return new Set((store?.users || [])
    .filter((user) =>
      getRoleId(user.role) === "author" &&
      getTenantIdFromUser(user) === getTenantIdFromUser(editorUser) &&
      String(user.managerUserId || "") === String(editorUser.id || "")
    )
    .map((user) => String(user.id || ""))
    .filter(Boolean));
}

function canUserAccessProjectMetadata(user, metadata) {
  if (!isUserAuthEnabled()) {
    return true;
  }
  if (!user || !metadata) {
    return false;
  }
  if (isPlatformAdmin(user)) {
    return true;
  }
  if (normalizeTenantId(metadata.tenantId) !== getTenantIdFromUser(user)) {
    return false;
  }
  const role = getRoleId(user.role);
  if (role === "tenant_admin") {
    return true;
  }
  const userId = String(user.id || "");
  const directUserIds = new Set([
    metadata.ownerUserId,
    metadata.authorUserId,
    metadata.editorUserId
  ].map((value) => String(value || "")).filter(Boolean));
  if (directUserIds.has(userId)) {
    return true;
  }
  if (role === "editor") {
    const managedAuthorIds = getManagedAuthorIdsForEditor(user);
    if (managedAuthorIds.has(metadata.ownerUserId) ||
        managedAuthorIds.has(metadata.authorUserId)) {
      return true;
    }
    return Boolean(metadata.legacyImported && !metadata.explicitOwnership);
  }
  if (role === "author") {
    return false;
  }
  if (role === "user") {
    return Boolean(metadata.legacyImported && !metadata.explicitOwnership);
  }
  return true;
}

function getProjectPublicMetadata(metadata) {
  if (!metadata) {
    return null;
  }
  return {
    bookName: metadata.bookName || "",
    tenantId: metadata.tenantId || "",
    tenantName: metadata.tenantName || "",
    ownerUserId: metadata.ownerUserId || "",
    ownerUsername: metadata.ownerUsername || "",
    ownerDisplayName: metadata.ownerDisplayName || "",
    authorUserId: metadata.authorUserId || "",
    authorUsername: metadata.authorUsername || "",
    editorUserId: metadata.editorUserId || "",
    editorUsername: metadata.editorUsername || "",
    createdByUserId: metadata.createdByUserId || "",
    createdByUsername: metadata.createdByUsername || "",
    createdAt: metadata.createdAt || "",
    updatedAt: metadata.updatedAt || "",
    explicitOwnership: Boolean(metadata.explicitOwnership),
    legacyImported: Boolean(metadata.legacyImported)
  };
}

function assertCurrentUserCanAccessProjectPaths(bookName, paths) {
  if (!isUserAuthEnabled()) {
    return getProjectMetadataForPaths(bookName, paths);
  }
  if (!fs.existsSync(paths.workspacePath)) {
    return getProjectMetadataForPaths(bookName, paths);
  }
  const metadata = getProjectMetadataForPaths(bookName, paths);
  if (!canUserAccessProjectMetadata(getCurrentUserContext(), metadata)) {
    throw new Error("Current user cannot access this project.");
  }
  return metadata;
}

function writeProjectMetadata(bookRoot, metadata) {
  const metadataPath = getProjectMetadataPath(bookRoot);
  fs.mkdirSync(path.dirname(metadataPath), { recursive: true });
  fs.writeFileSync(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`, "utf8");
  return metadata;
}

function buildProjectMetadataForActor(bookName, paths, actor = getCurrentUserContext(), existingMetadata = {}) {
  const role = getRoleId(actor?.role);
  const tenantId = getTenantIdFromUser(actor);
  const now = new Date().toISOString();
  const manager = role === "author" && actor?.managerUserId ? findUserById(actor.managerUserId) : null;
  return {
    version: 1,
    bookName,
    tenantId,
    tenantName: actor?.tenantName || getProjectTenantName(tenantId),
    ownerUserId: existingMetadata.ownerUserId || actor?.id || "",
    ownerUsername: existingMetadata.ownerUsername || actor?.username || "",
    ownerDisplayName: existingMetadata.ownerDisplayName || actor?.displayName || "",
    authorUserId: existingMetadata.authorUserId || (role === "author" ? actor?.id || "" : ""),
    authorUsername: existingMetadata.authorUsername || (role === "author" ? actor?.username || "" : ""),
    editorUserId: existingMetadata.editorUserId || (role === "editor" ? actor?.id || "" : manager?.id || ""),
    editorUsername: existingMetadata.editorUsername || (role === "editor" ? actor?.username || "" : manager?.username || ""),
    createdByUserId: existingMetadata.createdByUserId || actor?.id || "",
    createdByUsername: existingMetadata.createdByUsername || actor?.username || "",
    createdAt: existingMetadata.createdAt || now,
    updatedAt: now,
    workspaceRoot: getWorkspaceParentRootFromPaths(paths)
  };
}

function ensureProjectMetadataForCurrentUser(bookName, paths) {
  const currentMetadata = getProjectMetadataForPaths(bookName, paths);
  if (currentMetadata.explicitOwnership) {
    return currentMetadata;
  }
  const metadata = buildProjectMetadataForActor(bookName, paths, getCurrentUserContext(), currentMetadata);
  writeProjectMetadata(paths.bookRoot, metadata);
  return getProjectMetadataForPaths(bookName, paths);
}

function assertFileNameOnly(fileName, label = "fileName") {
  if (!fileName || typeof fileName !== "string") {
    throw new Error(`${label} is required.`);
  }
  if (fileName.includes("\0") || fileName !== path.basename(fileName)) {
    throw new Error(`Invalid ${label}.`);
  }
}

function normalizeSafeRelativePath(value, label = "fileName") {
  if (!value || typeof value !== "string") {
    throw new Error(`${label} is required.`);
  }
  if (value.includes("\0")) {
    throw new Error(`Invalid ${label}.`);
  }
  const clean = value.replace(/\\/g, "/").replace(/^\/+/, "");
  if (!clean || path.isAbsolute(clean)) {
    throw new Error(`Invalid ${label}.`);
  }
  const parts = clean.split("/");
  if (parts.some((part) => !part || part === "." || part === "..")) {
    throw new Error(`Invalid ${label}.`);
  }
  return parts.join("/");
}

function formatLocalTimestamp(date = new Date()) {
  const pad = (value) => String(value).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate())
  ].join("-") + " " + [
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds())
  ].join(":");
}

function formatFileStamp(date = new Date()) {
  return formatLocalTimestamp(date).replace(/[: ]/g, "-");
}

function formatCompactFileStamp(date = new Date()) {
  const pad = (value) => String(value).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds())
  ].join("");
}

function getUniqueFileName(dirPath, preferredFileName, date = new Date()) {
  const safeFileName = path.basename(String(preferredFileName || "file"));
  const preferredPath = resolveInside(dirPath, safeFileName);
  if (!fs.existsSync(preferredPath)) {
    return safeFileName;
  }
  const ext = path.extname(safeFileName);
  const stem = path.basename(safeFileName, ext);
  return `${stem}-${formatCompactFileStamp(date)}${ext}`;
}

function formatKdpFixReportWithHeader(reportText, { createdAt, bookName, source = {} } = {}) {
  const cleanOneLine = (value) => String(value || "").replace(/[\r\n]+/g, " ").trim();
  const sourceType = cleanOneLine(source.type || "");
  const sourceDirectory = cleanOneLine(source.directory || "");
  const sourceFileName = cleanOneLine(source.fileName || "");
  const sourceRelativePath = cleanOneLine(source.relativePath || "");
  const originalFileName = cleanOneLine(source.originalFileName || "");
  const header = [
    `# KDP 封面修改意见报告（生成时间：${createdAt}）`,
    "",
    `- BookName：${cleanOneLine(bookName) || "-"}`,
    `- 针对文件类型：${sourceType || "-"}`,
    `- 源文件目录：${sourceDirectory || "-"}`,
    `- 源文件名：${sourceFileName || "-"}`,
    `- 源文件路径：${sourceRelativePath || "-"}`,
    ...(originalFileName && originalFileName !== sourceFileName ? [`- 原始上传文件名：${originalFileName}`] : []),
    ""
  ];
  const body = String(reportText || "")
    .replace(/^# KDP 封面修改意见报告(?:（生成时间：\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}）)?\s*/u, "")
    .replace(/\n---\n生成时间：\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\s*$/u, "")
    .trimStart()
    .replace(/^(?:- (?:BookName|针对文件类型|源文件目录|源文件名|源文件路径|原始上传文件名)：[^\n]*\n)+\s*/u, "");
  return `${header.join("\n")}${body}`.trimEnd() + "\n";
}

function appendJsonLine(filePath, payload) {
  ensureDir(path.dirname(filePath));
  fs.appendFileSync(filePath, `${JSON.stringify(payload)}\n`, "utf8");
}

function readJsonFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  return JSON.parse(raw);
}

function readJsonLines(filePath) {
  if (!fs.existsSync(filePath)) {
    return [];
  }

  return fs.readFileSync(filePath, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function getRequestIp(req) {
  const forwarded = String(req?.headers?.["x-forwarded-for"] || "").split(",")[0].trim();
  return forwarded || req?.socket?.remoteAddress || "";
}

function getAuditUserInfo(user) {
  if (!user) {
    return null;
  }
  return {
    id: user.id || "",
    username: user.username || "",
    displayName: user.displayName || user.username || "",
    role: user.role || "",
    tenantId: user.tenantId || ""
  };
}

function sanitizeAuditData(data) {
  if (!data || typeof data !== "object") {
    return {};
  }
  try {
    const raw = JSON.stringify(data);
    if (raw.length > 3000) {
      return {
        truncated: true,
        preview: raw.slice(0, 3000)
      };
    }
    return JSON.parse(raw);
  } catch {
    return {
      summary: String(data).slice(0, 500)
    };
  }
}

function recordAuditEvent(action, details = {}) {
  if (!isUserAuthEnabled()) {
    return null;
  }
  try {
    const actorSource = Object.hasOwn(details, "actor") ? details.actor : getCurrentUserContext();
    const actor = getAuditUserInfo(actorSource);
    const targetUser = getAuditUserInfo(details.targetUser || null);
    const tenantId = normalizeTenantId(
      details.tenantId ||
      details.targetUser?.tenantId ||
      actorSource?.tenantId ||
      DEFAULT_TENANT_ID
    );
    const event = {
      id: randomUUID(),
      createdAt: new Date().toISOString(),
      action: String(action || "unknown"),
      status: details.status || "success",
      tenantId,
      actorUserId: actor?.id || "",
      actorUsername: actor?.username || "",
      actorRole: actor?.role || "",
      targetUserId: targetUser?.id || details.targetUserId || "",
      targetUsername: targetUser?.username || details.targetUsername || "",
      route: details.route || "",
      bookName: details.bookName || "",
      jobId: details.jobId || "",
      ip: details.req ? getRequestIp(details.req) : "",
      userAgent: details.req ? String(details.req.headers?.["user-agent"] || "").slice(0, 240) : "",
      message: String(details.message || "").slice(0, 500),
      data: sanitizeAuditData(details.data)
    };
    appendJsonLine(USER_AUDIT_LOG_PATH, event);
    return event;
  } catch {
    return null;
  }
}

function getAuditEvents({ limit = 100, action = "", user = "", status = "", actor = getCurrentUserContext() } = {}) {
  if (!isUserAuthEnabled()) {
    return [];
  }
  const safeLimit = Math.min(300, Math.max(1, Math.round(Number(limit) || 100)));
  const actionFilter = String(action || "").trim().toLowerCase();
  const userFilter = String(user || "").trim().toLowerCase();
  const statusFilter = String(status || "").trim().toLowerCase();
  const tenantFilter = isPlatformAdmin(actor) ? "" : getTenantIdFromUser(actor);
  return readJsonLines(USER_AUDIT_LOG_PATH)
    .filter((event) => {
      if (tenantFilter && normalizeTenantId(event.tenantId || DEFAULT_TENANT_ID) !== tenantFilter) {
        return false;
      }
      if (actionFilter && String(event.action || "").toLowerCase() !== actionFilter) {
        return false;
      }
      if (statusFilter && String(event.status || "").toLowerCase() !== statusFilter) {
        return false;
      }
      if (!userFilter) {
        return true;
      }
      return [
        event.actorUserId,
        event.actorUsername,
        event.targetUserId,
        event.targetUsername,
        event.tenantId,
        event.bookName,
        event.jobId
      ].some((value) => String(value || "").toLowerCase().includes(userFilter));
    })
    .slice(-safeLimit)
    .reverse()
    .map((event) => ({
      id: event.id || "",
      createdAt: event.createdAt || "",
      action: event.action || "",
      status: event.status || "",
      tenantId: event.tenantId || "",
      actorUserId: event.actorUserId || "",
      actorUsername: event.actorUsername || "",
      actorRole: event.actorRole || "",
      targetUserId: event.targetUserId || "",
      targetUsername: event.targetUsername || "",
      route: event.route || "",
      bookName: event.bookName || "",
      jobId: event.jobId || "",
      ip: event.ip || "",
      userAgent: event.userAgent || "",
      message: event.message || "",
      data: event.data && typeof event.data === "object" ? event.data : {}
    }));
}

function listFilesByExtensions(dirPath, extensions) {
  if (!fs.existsSync(dirPath)) {
    return [];
  }

  const normalized = extensions.map((ext) => ext.toLowerCase());
  return fs.readdirSync(dirPath)
    .filter((name) => {
      const ext = path.extname(name).toLowerCase();
      return normalized.includes(ext);
    })
    .sort((a, b) => a.localeCompare(b, "zh-Hans-CN"));
}

function listOutputDocuments(outputRoot) {
  if (!fs.existsSync(outputRoot)) {
    return [];
  }

  const results = [];
  const stack = [outputRoot];
  while (stack.length) {
    const current = stack.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    entries.forEach((entry) => {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        if (entry.name.toLowerCase() === "back") {
          return;
        }
        stack.push(fullPath);
        return;
      }

      const ext = path.extname(entry.name).toLowerCase();
      if (entry.name.startsWith("~$")) {
        return;
      }
      if (![".docx", ".epub", ".pdf"].includes(ext)) {
        return;
      }

      results.push(path.relative(outputRoot, fullPath));
    });
  }

  return results.sort((a, b) => a.localeCompare(b, "zh-Hans-CN"));
}

function parseFrontMatterMarkdown(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  const content = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---/);
  if (!match) {
    return null;
  }

  const data = {};
  match[1]
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .forEach((line) => {
      const colonIndex = line.indexOf(":");
      if (colonIndex <= 0) {
        return;
      }
      const key = line.slice(0, colonIndex).trim();
      const value = line.slice(colonIndex + 1).trim();
      data[key] = value;
    });

  return data;
}

function getChapterFiles(chapterRoot) {
  if (!fs.existsSync(chapterRoot)) {
    return [];
  }

  return fs.readdirSync(chapterRoot)
    .filter((name) => /^\d+\.md$/i.test(name))
    .sort((a, b) => {
      const aNumber = Number.parseInt(a, 10);
      const bNumber = Number.parseInt(b, 10);
      return aNumber - bNumber;
    });
}

function getChapterMetadata(chapterRoot) {
  return getChapterFiles(chapterRoot).map((fileName) => {
    const filePath = path.join(chapterRoot, fileName);
    const frontMatter = parseFrontMatterMarkdown(filePath) || {};
    return {
      fileName,
      chapterIndex: Number(frontMatter.chapter_index || Number.parseInt(fileName, 10) || 0),
      title: frontMatter.title || fileName
    };
  });
}

function deriveSummary(output, fallbackMessage) {
  const lines = output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  return lines.at(-1) || fallbackMessage;
}

function getCoverArtifacts(bookRoot) {
  const coverRoot = resolveCoverRoot(bookRoot, "ebook");
  const briefRoot = path.join(coverRoot, "brief");
  const draftRoot = path.join(coverRoot, "drafts");
  const reviewRoot = path.join(coverRoot, "reviews");
  const layoutRoot = path.join(coverRoot, "layout");
  const mockupRoot = path.join(coverRoot, "mockup");
  const finalRoot = path.join(coverRoot, "final");

  const reviewPath = path.join(reviewRoot, "cover_review.json");
  const reportPath = path.join(finalRoot, "cover_report.md");

  let review = null;
  if (fs.existsSync(reviewPath)) {
    try {
      review = readJsonFile(reviewPath);
    } catch {
      review = null;
    }
  }

  return {
    hasBrief: fs.existsSync(path.join(briefRoot, "cover_brief.json")),
    hasStrategy: fs.existsSync(path.join(briefRoot, "cover_strategy.json")),
    draftFiles: listFilesByExtensions(draftRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    layoutFiles: listFilesByExtensions(layoutRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    mockupFiles: listFilesByExtensions(mockupRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    finalFiles: listFilesByExtensions(finalRoot, [".png", ".jpg", ".jpeg", ".webp", ".pdf"]),
    kdpAcceptance: getKdpAcceptanceState(bookRoot),
    next: getNextCoverArtifacts(bookRoot),
    selectedReviewFiles: Array.isArray(review?.selected_files) ? review.selected_files : [],
    topCandidate: review?.summary?.top_candidate || "",
    reportText: fs.existsSync(reportPath) ? fs.readFileSync(reportPath, "utf8") : ""
  };
}

function getKdpAcceptanceRoot(bookRoot) {
  return path.join(bookRoot, "07_cover", "kdp_acceptance");
}

function getKdpCurrentSourcePath(root) {
  return path.join(root, "kdp_current_source.json");
}

function buildKdpCurrentSource({ type, directory = "07_cover/kdp_acceptance", fileName, relativePath, originalFileName = "" }) {
  const cleanRelativePath = String(relativePath || fileName || "").replace(/\\/g, "/").replace(/^\/+/, "");
  const cleanFileName = path.basename(cleanRelativePath || String(fileName || ""));
  const cleanDirName = path.posix.dirname(cleanRelativePath);
  const displayDirectory = cleanDirName && cleanDirName !== "."
    ? `${directory}/${cleanDirName}`
    : directory;
  return {
    type: String(type || path.extname(cleanFileName).replace(".", "") || "").toUpperCase(),
    origin: "KDP acceptance directory",
    directory: displayDirectory,
    fileName: cleanFileName,
    relativePath: cleanRelativePath ? `07_cover/kdp_acceptance/${cleanRelativePath}` : "",
    acceptanceRelativePath: cleanRelativePath,
    originalFileName: String(originalFileName || "")
  };
}

function writeKdpCurrentSource(root, source) {
  ensureDir(root);
  const next = {
    ...source,
    updatedAt: formatLocalTimestamp()
  };
  writeJsonFile(getKdpCurrentSourcePath(root), next);
  return next;
}

function readKdpCurrentSource(root) {
  return readJsonFileSafe(getKdpCurrentSourcePath(root));
}

function getKdpEffectiveCurrentSource(root) {
  const saved = readKdpCurrentSource(root);
  if (saved) {
    return saved;
  }
  const workbench = getKdpFixWorkbenchState(root);
  if (workbench?.sourceFileName && fs.existsSync(path.join(getKdpFixWorkbenchRoot(root), "source", workbench.sourceFileName))) {
    return writeKdpCurrentSource(root, buildKdpCurrentSource({
      type: "PNG",
      fileName: `fix_workbench/source/${workbench.sourceFileName}`,
      relativePath: `fix_workbench/source/${workbench.sourceFileName}`
    }));
  }
  const pngFiles = listFilesByExtensions(root, [".png"]);
  if (pngFiles.length) {
    const newest = pngFiles
      .map((fileName) => {
        const filePath = path.join(root, fileName);
        return { fileName, mtime: fs.statSync(filePath).mtimeMs };
      })
      .sort((a, b) => b.mtime - a.mtime)[0];
    if (newest) {
      return writeKdpCurrentSource(root, buildKdpCurrentSource({
        type: "PNG",
        fileName: newest.fileName,
        relativePath: newest.fileName
      }));
    }
  }
  return null;
}

function getKdpLatestLlmTextRegionsState(root) {
  const visionRoot = path.join(root, "llm_text_regions");
  const latestPath = path.join(visionRoot, "latest_llm_text_regions.json");
  const latest = readJsonFileSafe(latestPath);
  if (!latest) {
    return {
      hasLatest: false,
      latest: null
    };
  }
  const latestSlim = {
    bookName: latest.bookName || "",
    createdAt: latest.createdAt || "",
    model: latest.model || "",
    image: latest.image || null,
    modelImage: latest.modelImage || null,
    coordinateScale: latest.coordinateScale || { x: 1, y: 1 },
    regions: Array.isArray(latest.regions) ? latest.regions : [],
    usage: latest.usage || null,
    responseId: latest.responseId || "",
    responseStatus: latest.responseStatus || "",
    saved: {
      resultFileName: path.basename(latestPath),
      imageFileName: latest.image?.fileName || "",
      latestFileName: "latest_llm_text_regions.json",
      resultRelativePath: "07_cover/kdp_acceptance/llm_text_regions/latest_llm_text_regions.json",
      imageRelativePath: latest.image?.fileName ? `07_cover/kdp_acceptance/llm_text_regions/${latest.image.fileName}` : "",
      latestRelativePath: "07_cover/kdp_acceptance/llm_text_regions/latest_llm_text_regions.json",
      resultPath: latestPath,
      imagePath: latest.image?.path || "",
      latestPath
    }
  };
  return {
    hasLatest: true,
    latest: latestSlim
  };
}

function getKdpLatestFixReportState(root) {
  const reportRoot = path.join(root, "fix_reports");
  const latestJsonPath = path.join(reportRoot, "latest_kdp_fix_report.json");
  const latestTextPath = path.join(reportRoot, "latest_kdp_fix_report.md");
  const latest = readJsonFileSafe(latestJsonPath);
  const reportText = readTextIfExists(latestTextPath);
  if (!latest && !reportText) {
    return {
      hasLatest: false,
      latest: null
    };
  }
  return {
    hasLatest: true,
    latest: {
      bookName: latest?.bookName || "",
      createdAt: latest?.createdAt || "",
      reportText: reportText || latest?.reportText || "",
      spec: latest?.spec || null,
      textRegionCount: latest?.textRegionCount || 0,
      saved: {
        resultFileName: path.basename(latestJsonPath),
        textFileName: path.basename(latestTextPath),
        resultPath: latestJsonPath,
        textPath: latestTextPath,
        latestPath: latestJsonPath,
        backupDir: path.join(reportRoot, "back")
      }
    }
  };
}

function getKdpFixWorkbenchRoot(root) {
  return path.join(root, "fix_workbench");
}

function getKdpFixWorkbenchState(root) {
  const workRoot = getKdpFixWorkbenchRoot(root);
  const sourceRoot = path.join(workRoot, "source");
  const outputRoot = path.join(workRoot, "output");
  const cropRoot = path.join(workRoot, "crops");
  const fillRoot = path.join(workRoot, "fills");
  const compositeRoot = path.join(workRoot, "composites");
  const pdfRoot = path.join(workRoot, "pdfs");
  const promptRoot = path.join(workRoot, "prompts");
  const statePath = path.join(workRoot, "workbench_state.json");
  const savedState = readJsonFileSafe(statePath) || {};
  return {
    hasState: Boolean(savedState && Object.keys(savedState).length),
    ...savedState,
    sourceFiles: listFilesByExtensions(sourceRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    outputFiles: listFilesByExtensions(outputRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    cropFiles: listFilesByExtensions(cropRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    fillFiles: listFilesByExtensions(fillRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    compositeFiles: listFilesByExtensions(compositeRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    pdfFiles: listFilesByExtensions(pdfRoot, [".pdf"]),
    promptFiles: listFilesByExtensions(promptRoot, [".txt", ".md"]),
    roots: {
      workRoot,
      sourceRoot,
      outputRoot,
      cropRoot,
      fillRoot,
      compositeRoot,
      pdfRoot,
      promptRoot,
      statePath
    }
  };
}

function getKdpAcceptanceState(bookRoot) {
  const root = getKdpAcceptanceRoot(bookRoot);
  const reportPath = path.join(root, "kdp_acceptance_report.json");
  const reportTextPath = path.join(root, "kdp_acceptance_report.md");
  const report = readJsonFileSafe(reportPath);

  return {
    hasReport: Boolean(report),
    report,
    reportText: readTextIfExists(reportTextPath),
    currentSource: getKdpEffectiveCurrentSource(root),
    pdfFiles: listFilesByExtensions(root, [".pdf"]),
    llmTextRegions: getKdpLatestLlmTextRegionsState(root),
    fixReport: getKdpLatestFixReportState(root),
    fixWorkbench: getKdpFixWorkbenchState(root)
  };
}

function inchesToMm(value) {
  return Number((value * 25.4).toFixed(2));
}

function inchesToPoints(value) {
  return value * 72;
}

function normalizeNumber(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function getPaperbackSpineMultiplier(paperType) {
  switch (paperType) {
    case "bw-cream":
      return 0.0025;
    case "premium-color":
      return 0.002347;
    case "standard-color":
    case "bw-white":
    default:
      return 0.002252;
  }
}

function getPaperTypeLabel(paperType) {
  switch (paperType) {
    case "bw-cream":
      return "Black & white, cream paper";
    case "premium-color":
      return "Premium color paper";
    case "standard-color":
      return "Standard color paper";
    case "bw-white":
    default:
      return "Black & white, white paper";
  }
}

function buildKdpPaperbackCoverSpec(options = {}) {
  const trimWidthIn = normalizeNumber(options.trimWidthIn, 6);
  const trimHeightIn = normalizeNumber(options.trimHeightIn, 9);
  const bleedIn = normalizeNumber(options.bleedIn, 0.125);
  const pageCount = Math.max(1, Math.round(normalizeNumber(options.pageCount, 120)));
  const paperType = String(options.paperType || "bw-white");
  const multiplier = getPaperbackSpineMultiplier(paperType);
  const spineWidthIn = normalizeNumber(options.spineWidthIn, pageCount * multiplier);
  const coverWidthIn = bleedIn + trimWidthIn + spineWidthIn + trimWidthIn + bleedIn;
  const coverHeightIn = bleedIn + trimHeightIn + bleedIn;

  return {
    format: "paperback",
    trimWidthIn: Number(trimWidthIn.toFixed(3)),
    trimHeightIn: Number(trimHeightIn.toFixed(3)),
    bleedIn: Number(bleedIn.toFixed(3)),
    bleedMm: inchesToMm(bleedIn),
    pageCount,
    paperType,
    paperTypeLabel: getPaperTypeLabel(paperType),
    spineMultiplierIn: multiplier,
    spineWidthIn: Number(spineWidthIn.toFixed(3)),
    spineWidthMm: inchesToMm(spineWidthIn),
    expectedWidthIn: Number(coverWidthIn.toFixed(3)),
    expectedHeightIn: Number(coverHeightIn.toFixed(3)),
    expectedWidthPt: Number(inchesToPoints(coverWidthIn).toFixed(3)),
    expectedHeightPt: Number(inchesToPoints(coverHeightIn).toFixed(3)),
    expectedWidthMm: inchesToMm(coverWidthIn),
    expectedHeightMm: inchesToMm(coverHeightIn),
    spineTextAllowed: pageCount >= 79,
    formula: "Cover Width = Bleed + Back Cover Width + Spine Width + Front Cover Width + Bleed; Cover Height = Bleed + Trim Height + Bleed"
  };
}

function roundNumber(value, digits = 3) {
  return Number(Number(value || 0).toFixed(digits));
}

function buildKdpCoordinateMap(spec, dpi = 300) {
  const bleed = spec.bleedIn;
  const trimWidth = spec.trimWidthIn;
  const trimHeight = spec.trimHeightIn;
  const spine = spec.spineWidthIn;
  const fullWidth = spec.expectedWidthIn;
  const fullHeight = spec.expectedHeightIn;
  const safeInset = 0.125;
  const spineSafeInset = 0.0625;
  const barcodeWidth = 2;
  const barcodeHeight = 1.2;
  const barcodeInset = 0.25;
  const barcodeX = bleed + trimWidth - barcodeInset - barcodeWidth;
  const barcodeY = bleed + trimHeight - barcodeInset - barcodeHeight;
  const toPx = (value) => Math.round(value * dpi);
  const toMmValue = (value) => inchesToMm(value);
  const rect = (name, xIn, yIn, widthIn, heightIn, description) => ({
    name,
    description,
    inches: {
      x: roundNumber(xIn),
      y: roundNumber(yIn),
      width: roundNumber(widthIn),
      height: roundNumber(heightIn),
      right: roundNumber(xIn + widthIn),
      bottom: roundNumber(yIn + heightIn)
    },
    mm: {
      x: toMmValue(xIn),
      y: toMmValue(yIn),
      width: toMmValue(widthIn),
      height: toMmValue(heightIn),
      right: toMmValue(xIn + widthIn),
      bottom: toMmValue(yIn + heightIn)
    },
    px: {
      x: toPx(xIn),
      y: toPx(yIn),
      width: toPx(widthIn),
      height: toPx(heightIn),
      right: toPx(xIn + widthIn),
      bottom: toPx(yIn + heightIn)
    }
  });

  return {
    origin: "top-left of submitted PDF page",
    dpi,
    fullCover: rect("PDF full cover", 0, 0, fullWidth, fullHeight, "Submitted PDF page including bleed."),
    bleed: {
      leftIn: bleed,
      rightIn: bleed,
      topIn: bleed,
      bottomIn: bleed,
      leftPx: toPx(bleed),
      rightPx: toPx(bleed),
      topPx: toPx(bleed),
      bottomPx: toPx(bleed)
    },
    trimBox: rect("White trim box", bleed, bleed, (trimWidth * 2) + spine, trimHeight, "White dotted trim line / cut size after bleed is removed."),
    backCover: rect("Back cover trim", bleed, bleed, trimWidth, trimHeight, "Back cover final trim area."),
    spine: rect("Spine trim", bleed + trimWidth, bleed, spine, trimHeight, "Spine area between white spine-edge lines."),
    frontCover: rect("Front cover trim", bleed + trimWidth + spine, bleed, trimWidth, trimHeight, "Front cover final trim area."),
    backSafe: rect("Back cover red safe area", bleed + safeInset, bleed + safeInset, trimWidth - (safeInset * 2), trimHeight - (safeInset * 2), "Back cover text/logo safe area."),
    frontSafe: rect("Front cover red safe area", bleed + trimWidth + spine + safeInset, bleed + safeInset, trimWidth - (safeInset * 2), trimHeight - (safeInset * 2), "Front cover text/logo safe area."),
    spineSafe: rect("Spine red safe area", bleed + trimWidth + spineSafeInset, bleed + safeInset, Math.max(0, spine - (spineSafeInset * 2)), trimHeight - (safeInset * 2), "Spine text safe area."),
    barcodeBox: rect("KDP barcode box", barcodeX, barcodeY, barcodeWidth, barcodeHeight, "KDP automatic barcode reserve on the lower-right back cover: 2 x 1.2 in, 0.25 in from spine and bottom trim."),
    guideLines: {
      white: {
        trimLeftXIn: roundNumber(bleed),
        trimRightXIn: roundNumber(fullWidth - bleed),
        trimTopYIn: roundNumber(bleed),
        trimBottomYIn: roundNumber(fullHeight - bleed),
        spineLeftXIn: roundNumber(bleed + trimWidth),
        spineRightXIn: roundNumber(bleed + trimWidth + spine),
        trimLeftXPx: toPx(bleed),
        trimRightXPx: toPx(fullWidth - bleed),
        trimTopYPx: toPx(bleed),
        trimBottomYPx: toPx(fullHeight - bleed),
        spineLeftXPx: toPx(bleed + trimWidth),
        spineRightXPx: toPx(bleed + trimWidth + spine)
      },
      red: {
        safeLeftXIn: roundNumber(bleed + safeInset),
        safeRightXIn: roundNumber(fullWidth - bleed - safeInset),
        safeTopYIn: roundNumber(bleed + safeInset),
        safeBottomYIn: roundNumber(fullHeight - bleed - safeInset),
        spineSafeLeftXIn: roundNumber(bleed + trimWidth + spineSafeInset),
        spineSafeRightXIn: roundNumber(bleed + trimWidth + spine - spineSafeInset),
        safeLeftXPx: toPx(bleed + safeInset),
        safeRightXPx: toPx(fullWidth - bleed - safeInset),
        safeTopYPx: toPx(bleed + safeInset),
        safeBottomYPx: toPx(fullHeight - bleed - safeInset),
        spineSafeLeftXPx: toPx(bleed + trimWidth + spineSafeInset),
        spineSafeRightXPx: toPx(bleed + trimWidth + spine - spineSafeInset)
      }
    }
  };
}

function parsePdfBoxNumbers(match) {
  if (!match) {
    return null;
  }
  const values = match
    .slice(1, 5)
    .map((item) => Number.parseFloat(item));
  if (values.some((value) => !Number.isFinite(value))) {
    return null;
  }
  return values;
}

function extractPdfImageDpiCandidates(text, pdfWidthIn, pdfHeightIn) {
  const candidates = [];
  const imageRegex = /<<[\s\S]{0,2500}?\/Subtype\s*\/Image[\s\S]{0,2500}?>>/g;
  const matches = text.match(imageRegex) || [];

  matches.forEach((block) => {
    const width = Number.parseFloat(block.match(/\/Width\s+(\d+(?:\.\d+)?)/)?.[1] || "");
    const height = Number.parseFloat(block.match(/\/Height\s+(\d+(?:\.\d+)?)/)?.[1] || "");
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      return;
    }

    candidates.push({
      pixelWidth: Math.round(width),
      pixelHeight: Math.round(height),
      ifFullPageDpiX: Number((width / pdfWidthIn).toFixed(1)),
      ifFullPageDpiY: Number((height / pdfHeightIn).toFixed(1)),
      ifFullPageMinDpi: Number((Math.min(width / pdfWidthIn, height / pdfHeightIn)).toFixed(1))
    });
  });

  return candidates.sort((a, b) => (b.pixelWidth * b.pixelHeight) - (a.pixelWidth * a.pixelHeight));
}

function parsePdfInfo(filePath) {
  const buffer = fs.readFileSync(filePath);
  const text = buffer.toString("latin1");
  const version = text.match(/%PDF-(\d+(?:\.\d+)?)/)?.[1] || "";
  const pageMatches = text.match(/\/Type\s*\/Page\b(?!s)/g) || [];
  const mediaBox = parsePdfBoxNumbers(text.match(/\/MediaBox\s*\[\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\]/));
  const cropBox = parsePdfBoxNumbers(text.match(/\/CropBox\s*\[\s*(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s+(-?\d+(?:\.\d+)?)\s*\]/));
  const box = mediaBox || cropBox;
  if (!box) {
    throw new Error("Could not read PDF MediaBox or CropBox.");
  }

  const widthPt = Math.abs(box[2] - box[0]);
  const heightPt = Math.abs(box[3] - box[1]);
  const widthIn = widthPt / 72;
  const heightIn = heightPt / 72;
  const pageCount = pageMatches.length || null;
  const imageDpiCandidates = extractPdfImageDpiCandidates(text, widthIn, heightIn);

  return {
    version,
    pageCount,
    encrypted: /\/Encrypt\b/.test(text),
    hasAcroForm: /\/AcroForm\b/.test(text),
    hasCropBox: Boolean(cropBox),
    boxType: mediaBox ? "MediaBox" : "CropBox",
    widthPt: Number(widthPt.toFixed(3)),
    heightPt: Number(heightPt.toFixed(3)),
    widthIn: Number(widthIn.toFixed(3)),
    heightIn: Number(heightIn.toFixed(3)),
    widthMm: inchesToMm(widthIn),
    heightMm: inchesToMm(heightIn),
    imageDpiCandidates,
    largestImage: imageDpiCandidates[0] || null,
    fileSizeBytes: buffer.length
  };
}

function makeKdpCheck(status, title, detail) {
  return { status, title, detail };
}

function buildKdpAcceptanceReport({ bookName, pdfFileName, pdfPath, pdfInfo, spec }) {
  const toleranceIn = 0.01;
  const widthDelta = Number((pdfInfo.widthIn - spec.expectedWidthIn).toFixed(3));
  const heightDelta = Number((pdfInfo.heightIn - spec.expectedHeightIn).toFixed(3));
  const spineSafeWidthIn = Math.max(0, spec.spineWidthIn - 0.125);
  const requiredPixelWidth = Math.ceil(spec.expectedWidthIn * 300);
  const requiredPixelHeight = Math.ceil(spec.expectedHeightIn * 300);
  const coordinateMap = buildKdpCoordinateMap(spec, 300);
  const checks = [];

  checks.push(makeKdpCheck(
    "pass",
    "PDF file accepted for inspection",
    `${pdfFileName} (${Math.round(pdfInfo.fileSizeBytes / 1024)} KB)`
  ));

  if (pdfInfo.encrypted) {
    checks.push(makeKdpCheck("fail", "PDF is encrypted", "KDP print files should be upload-ready without password protection."));
  } else {
    checks.push(makeKdpCheck("pass", "PDF is not encrypted", "No /Encrypt marker was found."));
  }

  if (pdfInfo.pageCount === 1) {
    checks.push(makeKdpCheck("pass", "Cover PDF is one page", "A wraparound paperback cover should be submitted as one continuous cover PDF."));
  } else if (pdfInfo.pageCount) {
    checks.push(makeKdpCheck("fail", "Cover PDF is not one page", `Detected ${pdfInfo.pageCount} page objects.`));
  } else {
    checks.push(makeKdpCheck("warn", "Page count could not be confirmed", "The PDF dimensions were readable, but page object counting was inconclusive."));
  }

  if (Math.abs(widthDelta) <= toleranceIn && Math.abs(heightDelta) <= toleranceIn) {
    checks.push(makeKdpCheck(
      "pass",
      "Full cover size matches KDP formula",
      `PDF ${pdfInfo.widthIn} x ${pdfInfo.heightIn} in; expected ${spec.expectedWidthIn} x ${spec.expectedHeightIn} in.`
    ));
  } else {
    checks.push(makeKdpCheck(
      "fail",
      "Full cover size does not match KDP formula",
      `PDF ${pdfInfo.widthIn} x ${pdfInfo.heightIn} in; expected ${spec.expectedWidthIn} x ${spec.expectedHeightIn} in; delta ${widthDelta} x ${heightDelta} in.`
    ));
  }

  if (Math.abs(spec.bleedIn - 0.125) <= 0.001) {
    checks.push(makeKdpCheck("pass", "Bleed setting is KDP standard", "0.125 in / 3.2 mm bleed is required for covers."));
  } else {
    checks.push(makeKdpCheck("warn", "Bleed setting is not the usual KDP value", `Current bleed is ${spec.bleedIn} in. KDP cover guidance uses 0.125 in.`));
  }

  const largestImage = pdfInfo.largestImage;
  if (largestImage) {
    if (largestImage.ifFullPageMinDpi >= 300) {
      checks.push(makeKdpCheck(
        "pass",
        "Largest embedded image meets 300 DPI if used full-page",
        `Largest image is ${largestImage.pixelWidth} x ${largestImage.pixelHeight} px; full-cover requirement is about ${requiredPixelWidth} x ${requiredPixelHeight} px.`
      ));
    } else {
      checks.push(makeKdpCheck(
        "fail",
        "Largest embedded image may be below 300 DPI",
        `Largest image is ${largestImage.pixelWidth} x ${largestImage.pixelHeight} px, about ${largestImage.ifFullPageDpiX} x ${largestImage.ifFullPageDpiY} DPI if it spans the full cover. Full-cover target is at least ${requiredPixelWidth} x ${requiredPixelHeight} px.`
      ));
    }
  } else {
    checks.push(makeKdpCheck(
      "review",
      "300 DPI image resolution could not be verified",
      `KDP expects cover/manuscript images to be at least 300 DPI. For this cover size, a full-cover raster image should be at least ${requiredPixelWidth} x ${requiredPixelHeight} px. No embedded raster image dimensions were detected, so inspect the source/export settings.`
    ));
  }

  if (spec.spineTextAllowed) {
    checks.push(makeKdpCheck("info", "Spine text allowed by page count", `${spec.pageCount} pages is at least 79 pages; spine safe text width is about ${spineSafeWidthIn.toFixed(3)} in / ${inchesToMm(spineSafeWidthIn)} mm.`));
  } else {
    checks.push(makeKdpCheck("warn", "Spine text risk", "KDP only prints spine text on books with 79 pages or more."));
  }

  checks.push(makeKdpCheck(
    "review",
    "Spine text visual safety must be checked",
    "The file can pass size checks while still failing visually. Spine title, author, logo, and publisher marks must sit fully between the red spine safety lines and must not touch the white spine-edge/trim lines."
  ));
  checks.push(makeKdpCheck(
    "review",
    "Front/back text safe-zone review required",
    "All important text, logos, and barcode content must stay inside the red safe margin. Background art may extend to the PDF edge/bleed area."
  ));
  checks.push(makeKdpCheck(
    "manual",
    "Other manual visual checks still needed",
    "Confirm no white border, no crop marks, flattened layers, embedded fonts or rasterized text quality issues, readable text, and correct barcode area."
  ));

  const hasFail = checks.some((item) => item.status === "fail");
  const hasWarn = checks.some((item) => item.status === "warn");
  const hasReview = checks.some((item) => item.status === "review" || item.status === "manual");
  const technicalVerdict = hasFail ? "fail" : hasWarn ? "review" : "pass";
  const verdict = hasFail ? "fail" : hasWarn || hasReview ? "review" : "pass";

  return {
    generatedAt: formatLocalTimestamp(),
    bookName,
    pdfFileName,
    pdfPath,
    verdict,
    technicalVerdict,
    visualReviewRequired: hasReview,
    requiredResolution: {
      dpi: 300,
      fullCoverPixelWidth: requiredPixelWidth,
      fullCoverPixelHeight: requiredPixelHeight
    },
    coordinateMap,
    spec,
    pdf: pdfInfo,
    deltas: {
      widthIn: widthDelta,
      heightIn: heightDelta,
      toleranceIn
    },
    checks,
    sources: [
      {
        label: "Amazon KDP Paperback Submission Guidelines",
        url: "https://kdp.amazon.com/en_US/help/topic/G201857950"
      },
      {
        label: "Amazon KDP Fix Paperback and Hardcover Formatting Issues",
        url: "https://kdp.amazon.com/en_US/help/topic/G201834260"
      }
    ]
  };
}

function buildKdpAcceptanceMarkdown(report) {
  const statusLabel = {
    pass: "PASS",
    fail: "FAIL",
    warn: "WARN",
    review: "REVIEW",
    info: "INFO",
    manual: "MANUAL"
  };
  const lines = [];
  lines.push("# KDP Acceptance Report");
  lines.push("");
  lines.push(`- BookName: ${report.bookName}`);
  lines.push(`- PDF: ${report.pdfFileName}`);
  lines.push(`- Verdict: ${statusLabel[report.verdict] || report.verdict}`);
  lines.push(`- Technical size verdict: ${statusLabel[report.technicalVerdict] || report.technicalVerdict || "unknown"}`);
  lines.push(`- Visual review required: ${report.visualReviewRequired ? "yes" : "no"}`);
  lines.push(`- Generated: ${report.generatedAt}`);
  lines.push("");
  lines.push("## Expected Cover Size");
  lines.push("");
  lines.push(`- Trim: ${report.spec.trimWidthIn} x ${report.spec.trimHeightIn} in`);
  lines.push(`- Page count: ${report.spec.pageCount}`);
  lines.push(`- Paper: ${report.spec.paperTypeLabel}`);
  lines.push(`- Spine: ${report.spec.spineWidthIn} in / ${report.spec.spineWidthMm} mm`);
  lines.push(`- Bleed: ${report.spec.bleedIn} in / ${report.spec.bleedMm} mm`);
  lines.push(`- Full cover: ${report.spec.expectedWidthIn} x ${report.spec.expectedHeightIn} in`);
  lines.push(`- Full cover: ${report.spec.expectedWidthMm} x ${report.spec.expectedHeightMm} mm`);
  lines.push("");
  lines.push("## Uploaded PDF");
  lines.push("");
  lines.push(`- Page box: ${report.pdf.boxType}`);
  lines.push(`- Page count: ${report.pdf.pageCount || "unknown"}`);
  lines.push(`- Size: ${report.pdf.widthIn} x ${report.pdf.heightIn} in`);
  lines.push(`- Size: ${report.pdf.widthMm} x ${report.pdf.heightMm} mm`);
  lines.push(`- Delta: ${report.deltas.widthIn} x ${report.deltas.heightIn} in`);
  lines.push(`- Required raster baseline: ${report.requiredResolution.fullCoverPixelWidth} x ${report.requiredResolution.fullCoverPixelHeight} px at ${report.requiredResolution.dpi} DPI`);
  if (report.pdf.largestImage) {
    lines.push(`- Largest embedded image: ${report.pdf.largestImage.pixelWidth} x ${report.pdf.largestImage.pixelHeight} px`);
    lines.push(`- Largest image full-page effective DPI: ${report.pdf.largestImage.ifFullPageDpiX} x ${report.pdf.largestImage.ifFullPageDpiY}`);
  } else {
    lines.push("- Largest embedded image: not detected");
  }
  lines.push("");
  lines.push("## PDF Coordinate Map");
  lines.push("");
  lines.push(`- Origin: ${report.coordinateMap.origin}`);
  lines.push(`- Coordinate DPI: ${report.coordinateMap.dpi}`);
  [
    report.coordinateMap.fullCover,
    report.coordinateMap.trimBox,
    report.coordinateMap.backCover,
    report.coordinateMap.spine,
    report.coordinateMap.frontCover,
    report.coordinateMap.backSafe,
    report.coordinateMap.spineSafe,
    report.coordinateMap.frontSafe
  ].forEach((item) => {
    lines.push(`- ${item.name}: ${item.inches.width} x ${item.inches.height} in; x=${item.inches.x}, y=${item.inches.y}; px x=${item.px.x}, y=${item.px.y}, w=${item.px.width}, h=${item.px.height}`);
  });
  lines.push("");
  lines.push("## Checks");
  lines.push("");
  report.checks.forEach((check) => {
    lines.push(`- [${statusLabel[check.status] || check.status}] ${check.title}: ${check.detail}`);
  });
  lines.push("");
  lines.push("## KDP Sources");
  report.sources.forEach((source) => {
    lines.push(`- ${source.label}: ${source.url}`);
  });
  return `${lines.join("\r\n")}\r\n`;
}

function extractResponseText(response) {
  if (typeof response?.output_text === "string") {
    return response.output_text;
  }
  const parts = [];
  (response?.output || []).forEach((item) => {
    (item?.content || []).forEach((content) => {
      if (typeof content?.text === "string") {
        parts.push(content.text);
      }
    });
  });
  return parts.join("\n").trim();
}

function parseJsonFromModelText(text) {
  const raw = String(text || "").trim();
  if (!raw) {
    throw new Error("Model returned empty text.");
  }
  try {
    return JSON.parse(raw);
  } catch {
    const match = raw.match(/```(?:json)?\s*([\s\S]*?)```/) || raw.match(/(\{[\s\S]*\})/);
    if (!match) {
      throw new Error("Model did not return JSON.");
    }
    return JSON.parse(match[1]);
  }
}

function normalizeVisionRegion(region, index, imageWidth, imageHeight, coordinateScale = { x: 1, y: 1 }) {
  const rawX = Number(region.x ?? region.left ?? 0);
  const rawY = Number(region.y ?? region.top ?? 0);
  const rawWidth = Number(region.width ?? region.w ?? 0);
  const rawHeight = Number(region.height ?? region.h ?? 0);
  const rawRight = Number(region.right ?? (rawX + rawWidth));
  const rawBottom = Number(region.bottom ?? (rawY + rawHeight));
  const x = Math.max(0, Math.round(rawX * coordinateScale.x));
  const y = Math.max(0, Math.round(rawY * coordinateScale.y));
  const width = Math.max(0, Math.round(rawWidth * coordinateScale.x));
  const height = Math.max(0, Math.round(rawHeight * coordinateScale.y));
  const scaledRight = rawRight * coordinateScale.x;
  const scaledBottom = rawBottom * coordinateScale.y;
  const finalRight = Math.min(imageWidth, Math.round(Number.isFinite(scaledRight) ? scaledRight : (x + width)));
  const finalBottom = Math.min(imageHeight, Math.round(Number.isFinite(scaledBottom) ? scaledBottom : (y + height)));
  const normalizedWidth = Math.max(0, finalRight - x || width);
  const normalizedHeight = Math.max(0, finalBottom - y || height);

  return {
    id: String(region.id || `llm-${index + 1}`),
    zone: "unclassified",
    text: String(region.text || "").trim(),
    confidence: Number(Number(region.confidence ?? 0.75).toFixed(2)),
    orientation: String(region.orientation || "unknown"),
    x,
    y,
    width: normalizedWidth,
    height: normalizedHeight,
    right: Math.min(imageWidth, x + normalizedWidth),
    bottom: Math.min(imageHeight, y + normalizedHeight),
    source: "llm_vision",
    notes: String(region.notes || ""),
    raw: {
      x: rawX,
      y: rawY,
      width: rawWidth,
      height: rawHeight,
      right: rawRight,
      bottom: rawBottom
    },
    coordinateScale: {
      x: coordinateScale.x,
      y: coordinateScale.y
    }
  };
}

function getNextCoverArtifacts(bookRoot, edition = "ebook") {
  const nextRoot = path.join(bookRoot, "07_cover", "next", edition);
  const nextPrintRoot = path.join(bookRoot, "07_cover", "next", "print");
  const baseRoot = path.join(nextRoot, "base");
  const promptRoot = path.join(nextRoot, "prompts");
  const importRoot = path.join(nextRoot, "imports");
  const reviewRoot = path.join(nextRoot, "reviews");
  const layoutRoot = path.join(nextRoot, "layout");
  const printRoot = path.join(nextPrintRoot, "print_spread");
  const mockupRoot = path.join(nextRoot, "mockup");
  const finalRoot = path.join(nextRoot, "final");
  const finalReportPath = path.join(finalRoot, "next_cover_report.md");
  const promptReportPath = path.join(promptRoot, "midjourney_prompt_report.md");
  const imageEditReportPath = path.join(layoutRoot, "ai_image_edit_report.md");
  const reportParts = [promptReportPath, imageEditReportPath, finalReportPath]
    .filter((item) => fs.existsSync(item))
    .map((item) => fs.readFileSync(item, "utf8"));

  return {
    edition,
    hasBaseBrief: fs.existsSync(path.join(baseRoot, "base_brief.json")),
    hasPrompts: fs.existsSync(path.join(promptRoot, "base_prompts.json")) ||
      fs.existsSync(path.join(promptRoot, "midjourney_prompt.txt")),
    hasReview: fs.existsSync(path.join(reviewRoot, "base_review.json")),
    importFiles: listFilesByExtensions(importRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    layoutFiles: listFilesByExtensions(layoutRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    printSpreadFiles: listFilesByExtensions(printRoot, [".png", ".jpg", ".jpeg", ".webp", ".pdf"]),
    mockupFiles: listFilesByExtensions(mockupRoot, [".png", ".jpg", ".jpeg", ".webp"]),
    finalFiles: listFilesByExtensions(finalRoot, [".png", ".jpg", ".jpeg", ".webp", ".pdf"]),
    reportText: reportParts.join("\r\n\r\n---\r\n\r\n")
  };
}

function getLatestFileByExtensions(dirPath, extensions) {
  if (!fs.existsSync(dirPath)) {
    return "";
  }

  const normalized = extensions.map((ext) => ext.toLowerCase());
  const files = fs.readdirSync(dirPath, { withFileTypes: true })
    .filter((entry) => entry.isFile() && normalized.includes(path.extname(entry.name).toLowerCase()))
    .map((entry) => {
      const fullPath = path.join(dirPath, entry.name);
      return { name: entry.name, mtime: fs.statSync(fullPath).mtimeMs };
    })
    .sort((a, b) => b.mtime - a.mtime);

  return files[0]?.name || "";
}

function getCoverWorkbenchState(bookRoot, edition = "ebook") {
  const nextRoot = path.join(bookRoot, "07_cover", "next", edition);
  const promptRoot = path.join(nextRoot, "prompts");
  const importRoot = path.join(nextRoot, "imports");
  const layoutRoot = path.join(nextRoot, "layout");
  const oldCoverRoot = resolveCoverRoot(bookRoot, "ebook");
  const oldBriefRoot = path.join(oldCoverRoot, "brief");
  const statePath = path.join(nextRoot, "workbench_state.json");
  const promptPath = path.join(promptRoot, "midjourney_prompt.txt");
  const legacyPromptPath = path.join(oldBriefRoot, "cover_midjourney_prompt.txt");
  const assistantJsonPath = path.join(oldBriefRoot, "cover_assistant_last.json");
  const assistantMdPath = path.join(oldBriefRoot, "cover_assistant_last.md");
  const imageEditReportPath = path.join(layoutRoot, "ai_image_edit_report.json");
  const savedState = readJsonFileSafe(statePath) || {};
  const imageEditReport = readJsonFileSafe(imageEditReportPath) || {};
  const importFiles = listFilesByExtensions(importRoot, [".png", ".jpg", ".jpeg", ".webp"]);

  const latestImport = savedState.latest_import_file ||
    getLatestFileByExtensions(importRoot, [".png", ".jpg", ".jpeg", ".webp"]);
  const selectedImport = importFiles.includes(savedState.selected_import_file)
    ? savedState.selected_import_file
    : latestImport;
  const latestEdited = savedState.latest_edited_file ||
    path.basename(String(imageEditReport.output_image || "")) ||
    getLatestFileByExtensions(layoutRoot, [".png", ".jpg", ".jpeg", ".webp"]);

  return {
    edition,
    prompt: readTextIfExists(promptPath) || readTextIfExists(legacyPromptPath),
    assistantRequest: savedState.assistant_request || "",
    assistantResponse: readTextIfExists(assistantMdPath),
    assistantResult: readJsonFileSafe(assistantJsonPath),
    editText: savedState.edit_text || imageEditReport.cover_text?.raw || "",
    publisher: savedState.publisher || imageEditReport.cover_text?.publisher || "",
    imageModel: savedState.image_model || imageEditReport.image_model || "gpt-image-1.5",
    importFiles,
    selectedImportFile: selectedImport,
    latestImportFile: latestImport,
    latestEditedFile: latestEdited,
    statePath,
    imageEditReport
  };
}

function getFrontmatterPayload(paths) {
  const readText = (filePath) => (fs.existsSync(filePath) ? fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "") : "");
  let manifest = null;
  if (fs.existsSync(paths.frontmatterManifestPath)) {
    try {
      manifest = readJsonFile(paths.frontmatterManifestPath);
    } catch {
      manifest = null;
    }
  }

  return {
    manifest,
    coverPage: readText(paths.coverPagePath),
    titlePage: readText(paths.titlePagePath),
    copyrightPage: readText(paths.copyrightPagePath)
  };
}

function listDirectories(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return [];
  }

  return fs.readdirSync(dirPath, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b, "zh-Hans-CN"));
}

function listDirectFiles(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return [];
  }

  return fs.readdirSync(dirPath, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b, "zh-Hans-CN"));
}

function readTextIfExists(filePath) {
  if (!fs.existsSync(filePath)) {
    return "";
  }
  return fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
}

function readJsonFileSafe(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }

  try {
    return readJsonFile(filePath);
  } catch {
    return null;
  }
}

function getStringValue(value) {
  if (value === undefined || value === null) {
    return "";
  }
  return String(value).trim();
}

function getStringArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value
    .map((item) => getStringValue(item))
    .filter(Boolean);
}

function uniqueStrings(values) {
  return [...new Set(values.map((item) => getStringValue(item)).filter(Boolean))];
}

function joinClause(values, limit = 6) {
  return uniqueStrings(values).slice(0, limit).join(", ");
}

function buildCoverMidjourneyPrompt(paths, overrides = {}) {
  const briefPath = path.join(paths.coverBriefRoot, "cover_brief.json");
  const strategyPath = path.join(paths.coverBriefRoot, "cover_strategy.json");
  const brief = readJsonFileSafe(briefPath) || {};
  const strategy = readJsonFileSafe(strategyPath) || {};
  const copy = readJsonFileSafe(paths.coverCopyJsonPath) || {};

  const title =
    getStringValue(overrides.title) ||
    getStringValue(brief.cover_text?.title) ||
    getStringValue(strategy.cover_text?.title);
  const subtitle =
    getStringValue(overrides.subtitle) ||
    getStringValue(copy.selected?.subtitle) ||
    getStringValue(brief.cover_text?.subtitle) ||
    getStringValue(strategy.cover_text?.subtitle);
  const author =
    getStringValue(overrides.author) ||
    getStringValue(brief.cover_text?.author) ||
    getStringValue(strategy.cover_text?.author);

  const metadata = brief.metadata || {};
  const positioning = brief.positioning || {};
  const primary = strategy.primary_strategy || {};
  const promptPackage = strategy.generation_plan?.prompt_package || {};
  const routePrompts = Array.isArray(promptPackage.route_prompts) ? promptPackage.route_prompts : [];
  const routePrompt =
    routePrompts.find((item) => getStringValue(item.route_id) === getStringValue(primary.route_id)) ||
    routePrompts[0] ||
    null;

  const visualDirection = joinClause([
    ...getStringArray(primary.main_visual),
    ...getStringArray(brief.design_directions?.[0]?.visual_keywords)
  ], 8);
  const colorDirection = joinClause([
    ...getStringArray(primary.color_direction),
    ...getStringArray(brief.design_directions?.[0]?.palette)
  ], 6);
  const moodDirection = joinClause([
    ...getStringArray(positioning.reader_impression),
    ...getStringArray(brief.design_directions?.[0]?.mood_keywords)
  ], 8);
  const topKeywords = joinClause(getStringArray(metadata.top_keywords), 8);
  const negativePrompt = joinClause([
    ...getStringArray(promptPackage.negative_prompt),
    ...getStringArray(positioning.avoid),
    "text",
    "typography",
    "letters",
    "subtitle",
    "author name",
    "watermark",
    "logo"
  ], 16);

  const clauses = [
    "book cover base image for a serious nonfiction book, image-only background, no typography on the image",
    title ? `inspired by the book title "${title}"` : "",
    subtitle ? `subtitle context: ${subtitle}` : "",
    author ? `author context: ${author}` : "",
    getStringValue(metadata.book_type) ? `book type: ${getStringValue(metadata.book_type)}` : "",
    getStringValue(metadata.audience) ? `target audience: ${getStringValue(metadata.audience)}` : "",
    getStringValue(metadata.core_thesis) ? `core thesis: ${getStringValue(metadata.core_thesis)}` : "",
    getStringValue(metadata.scope) ? `scope: ${getStringValue(metadata.scope)}` : "",
    getStringValue(metadata.style) ? `style tone: ${getStringValue(metadata.style)}` : "",
    visualDirection ? `visual direction: ${visualDirection}` : "",
    getStringValue(primary.composition) ? `composition: ${getStringValue(primary.composition)}` : "",
    colorDirection ? `color palette: ${colorDirection}` : "",
    moodDirection ? `mood: ${moodDirection}` : "",
    topKeywords ? `keywords: ${topKeywords}` : "",
    getStringValue(primary.route_label) ? `route: ${getStringValue(primary.route_label)}` : "",
    getStringValue(routePrompt?.prompt_draft) ? `draft prompt seed: ${getStringValue(routePrompt.prompt_draft)}` : "",
    "premium publishing quality, clean focal hierarchy, clear subject silhouette, high detail, modern structured knowledge aesthetic, elegant lighting, high contrast, thumbnail-friendly",
    negativePrompt ? `--no ${negativePrompt}` : "",
    "--ar 2:3 --stylize 150 --v 7"
  ];

  return clauses.filter(Boolean).join(", ");
}

function getPublishLanguageRoot(bookRoot, languageCode) {
  return path.join(bookRoot, "09_publish", languageCode);
}

function getLocalizedAmazonDescriptionSourcePath(bookRoot, languageCode = "zh") {
  const normalized = String(languageCode || "zh").trim().toLowerCase();
  if (normalized === "zh") {
    return path.join(bookRoot, "00_brief", "amazon_description.md");
  }
  return path.join(bookRoot, "03_translation", normalized, "00_brief", "amazon_description.md");
}

function extractMarkdownBody(content) {
  const raw = String(content || "").replace(/^\uFEFF/, "").replace(/\r/g, "");
  const match = raw.match(/^---\n[\s\S]*?\n---\n?/);
  if (match) {
    return raw.slice(match[0].length).trim();
  }
  return raw.trim();
}

function getOutputLanguages(bookRoot) {
  const outputRoot = path.join(bookRoot, "04_output");
  if (!fs.existsSync(outputRoot)) {
    return [];
  }

  const languages = [];
  const directOutputFiles = fs.readdirSync(outputRoot, { withFileTypes: true })
    .filter((entry) => entry.isFile())
    .map((entry) => entry.name)
    .filter((name) => !name.startsWith("~$"))
    .filter((name) => /\.(docx|epub|pdf)$/i.test(name));

  if (directOutputFiles.length) {
    languages.push("zh");
  }

  fs.readdirSync(outputRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name !== "back")
    .map((entry) => entry.name.trim().toLowerCase())
    .filter(Boolean)
    .sort((a, b) => a.localeCompare(b, "zh-Hans-CN"))
    .forEach((language) => {
      if (!languages.includes(language)) {
        languages.push(language);
      }
    });

  return languages;
}

function getPublishArtifacts(bookRoot, languageCode = "zh") {
  const publishBaseRoot = path.join(bookRoot, "09_publish");
  const publishRoot = getPublishLanguageRoot(bookRoot, languageCode);
  const availableLanguages = listDirectories(publishBaseRoot);
  const sourceLanguages = getOutputLanguages(bookRoot);
  const manifestPath = path.join(publishRoot, "publish_manifest.json");
  const metadataJsonPath = path.join(publishRoot, "publish_metadata.json");
  const metadataMdPath = path.join(publishRoot, "publish_metadata.md");
  const reportPath = path.join(publishRoot, "publish_report.md");
  const amazonDescriptionSourcePath = getLocalizedAmazonDescriptionSourcePath(bookRoot, languageCode);
  const amazonDescriptionSourceMarkdown = readTextIfExists(amazonDescriptionSourcePath);
  const amazonDescriptionSourceText = extractMarkdownBody(amazonDescriptionSourceMarkdown);

  const platformConfig = {
    amazon: {
      packageFile: "amazon_kdp_package.json",
      checklistFile: "amazon_submission_checklist.md",
      descriptionFile: "amazon_description.txt",
      keywordsFile: "amazon_keywords.txt"
    },
    apple: {
      packageFile: "apple_books_package.json",
      checklistFile: "apple_submission_checklist.md",
      descriptionFile: "apple_store_description.txt",
      keywordsFile: "apple_keywords.txt"
    },
    google: {
      packageFile: "google_play_books_package.json",
      checklistFile: "google_submission_checklist.md",
      descriptionFile: "google_store_description.txt",
      keywordsFile: "google_keywords.txt"
    }
  };

  const platforms = Object.fromEntries(
    Object.entries(platformConfig).map(([platformName, config]) => {
      const platformRoot = path.join(publishRoot, platformName);
      return [platformName, {
        exists: fs.existsSync(platformRoot),
        folder: fs.existsSync(platformRoot) ? path.relative(bookRoot, platformRoot) : "",
        files: listDirectFiles(platformRoot),
        packageJson: readJsonFileSafe(path.join(platformRoot, config.packageFile)),
        checklistText: readTextIfExists(path.join(platformRoot, config.checklistFile)),
        descriptionText: readTextIfExists(path.join(platformRoot, config.descriptionFile)),
        descriptionHtml: platformName === "amazon"
          ? readTextIfExists(path.join(platformRoot, "amazon_description.html"))
          : "",
        descriptionSourceMarkdown: platformName === "amazon" ? amazonDescriptionSourceMarkdown : "",
        descriptionSourceText: platformName === "amazon" ? amazonDescriptionSourceText : "",
        descriptionSourcePath: platformName === "amazon" && fs.existsSync(amazonDescriptionSourcePath)
          ? path.relative(bookRoot, amazonDescriptionSourcePath)
          : "",
        keywordsText: readTextIfExists(path.join(platformRoot, config.keywordsFile))
      }];
    })
  );

  return {
    exists: fs.existsSync(publishRoot),
    language: languageCode,
    availableLanguages,
    sourceLanguages,
    root: fs.existsSync(publishRoot) ? path.relative(bookRoot, publishRoot) : "",
    rootFiles: listDirectFiles(publishRoot),
    manifest: readJsonFileSafe(manifestPath),
    metadataJson: readJsonFileSafe(metadataJsonPath),
    metadataMarkdown: readTextIfExists(metadataMdPath),
    reportText: readTextIfExists(reportPath),
    platforms
  };
}

function writeJsonFile(filePath, payload) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
}

function sanitizeText(value) {
  return String(value || "").trim();
}

function escapeHtmlText(value) {
  return String(value || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function convertPlainTextToAmazonHtml(text) {
  const normalized = String(text || "").replace(/\r/g, "").trim();
  if (!normalized) {
    return "";
  }

  const paragraphs = normalized
    .split(/\n{2,}/)
    .map((part) => part.split(/\n+/).map((line) => line.trim()).filter(Boolean))
    .filter((lines) => lines.length);

  return paragraphs.map((lines) => {
    const isBulletBlock = lines.every((line) => /^[-*•]\s+/.test(line));
    if (isBulletBlock) {
      const items = lines
        .map((line) => line.replace(/^[-*•]\s+/, "").trim())
        .filter(Boolean)
        .map((line) => `  <li>${escapeHtmlText(line)}</li>`)
        .join("\n");
      return `<ul>\n${items}\n</ul>`;
    }

    return `<p>${escapeHtmlText(lines.join(" "))}</p>`;
  }).join("\n\n");
}

function sanitizeList(input) {
  const items = Array.isArray(input)
    ? input
    : String(input || "").split(/\r?\n|,/);

  return [...new Set(items
    .map((item) => String(item || "").trim())
    .filter(Boolean))];
}

function splitPersonName(fullName) {
  const parts = String(fullName || "").trim().split(/\s+/).filter(Boolean);
  if (!parts.length) {
    return { firstName: "", lastName: "" };
  }
  if (parts.length === 1) {
    return { firstName: parts[0], lastName: "" };
  }
  return {
    firstName: parts.slice(0, -1).join(" "),
    lastName: parts.slice(-1).join("")
  };
}

function buildKoboAccountBasicInfoMarkdown({
  bookName,
  language,
  metadata,
  objectiveData
}) {
  const author = String(metadata?.author || objectiveData?.author || "").trim();
  const publisher = String(metadata?.publisher || author || "").trim();
  const title = String(metadata?.title || objectiveData?.title || "").trim();
  const parsedName = splitPersonName(author);
  const generatedAt = new Date().toISOString();

  const lines = [
    "# Kobo Account Basic Info",
    "",
    "这份文件用于辅助创建 Kobo Writing Life / Kobo Author 账号时，先整理需要人工填写的基本信息。",
    "",
    "## Source",
    `- BookName: ${bookName || ""}`,
    `- Language: ${language || ""}`,
    `- Title: ${title || ""}`,
    `- Author: ${author || ""}`,
    `- Publisher: ${publisher || ""}`,
    `- Generated At: ${generatedAt}`,
    "",
    "## Kobo Portal",
    "- Entry: https://www.kobo.com/writinglife",
    "",
    "## Your Primary Contact",
    `- First Name: ${parsedName.firstName || ""}`,
    `- Last Name: ${parsedName.lastName || ""}`,
    `- Publisher Name: ${publisher || ""}`,
    "- Email Address: ",
    "",
    "## Your Location",
    "- Country: ",
    "- Street Address: ",
    "- Street Address 2: ",
    "- Province/State: ",
    "- City: ",
    "- Postal / Zip Code: ",
    "",
    "## Your Email Preferences",
    "- Receive Kobo-related emails: [ ] Yes  [ ] No",
    "",
    "## Manual Check",
    "- Confirm the contact name used for the Kobo account.",
    "- Confirm the publisher name shown publicly on Kobo.",
    "- Confirm the signup email address.",
    "- Confirm the billing / tax / postal information before提交.",
    "",
    "## Notes",
    "- 这份 MD 会先预填系统里已经有的作者 / 出版方信息。",
    "- 邮箱、地址、国家、邮编等仍需要你人工确认与填写。",
    ""
  ];

  return lines.join("\r\n");
}

function buildAmazonDescriptionSourceMarkdown({ metadata = {}, language = "zh", descriptionText = "" }) {
  const lines = [
    "---",
    "file_role: amazon_description",
    "layer: marketing",
    `title: ${getStringValue(metadata.title)}`,
    `subtitle: ${getStringValue(metadata.subtitle)}`,
    `author: ${getStringValue(metadata.author)}`,
    `language: ${String(language || "zh").trim() || "zh"}`,
    `updated_at: ${formatLocalTimestamp()}`,
    "---",
    "",
    String(descriptionText || "").trim()
  ];
  return `${lines.join("\r\n").trim()}\r\n`;
}

function buildPublishMetadataMarkdown(metadata) {
  const lines = [];
  lines.push("# Publish Metadata");
  lines.push("");
  lines.push(`- Title: ${metadata.title || ""}`);
  lines.push(`- Subtitle: ${metadata.subtitle || ""}`);
  lines.push(`- Author: ${metadata.author || ""}`);
  lines.push(`- Language: ${metadata.language || ""}`);
  lines.push(`- Publication Date: ${metadata.publication_date || ""}`);
  lines.push(`- Publisher: ${metadata.publisher || ""}`);
  lines.push(`- Imprint: ${metadata.imprint || ""}`);
  lines.push(`- Edition Type: ${metadata.edition_type || ""}`);
  lines.push("");
  lines.push("## Rights");
  lines.push("");
  lines.push(metadata.rights || "");
  lines.push("");
  lines.push(`- Copyright Holder: ${metadata.copyright_holder || ""}`);
  lines.push(`- Territory: ${metadata.territory || ""}`);
  lines.push(`- Distribution Rights: ${metadata.distribution_rights || ""}`);
  lines.push("");
  lines.push("## Marketing");
  lines.push("");
  lines.push(`- Tagline: ${metadata.marketing_tagline || ""}`);
  lines.push(`- Cover Hook: ${metadata.cover_hook || ""}`);
  lines.push(`- OBI Copy: ${metadata.obi_copy || ""}`);
  lines.push(`- Spine Text: ${metadata.spine_text || ""}`);
  lines.push("");
  lines.push("## Short Description");
  lines.push("");
  lines.push(metadata.short_description || "");
  lines.push("");
  lines.push("## Long Description");
  lines.push("");
  lines.push(metadata.long_description || "");
  lines.push("");
  lines.push("## Back Cover Blurb");
  lines.push("");
  lines.push(metadata.back_cover_blurb || "");
  lines.push("");
  lines.push("## Author Bio");
  lines.push("");
  lines.push(metadata.author_bio || "");
  lines.push("");
  lines.push("## Keywords");
  lines.push("");
  (metadata.keywords || []).forEach((item) => lines.push(`- ${item}`));
  lines.push("");
  lines.push("## Categories");
  lines.push("");
  (metadata.categories || []).forEach((item) => lines.push(`- ${item}`));
  lines.push("");
  lines.push("## Formats");
  lines.push("");
  (metadata.formats || []).forEach((item) => lines.push(`- ${item}`));
  return lines.join("\r\n");
}

function buildPublishReportMarkdown(metadata, manifest) {
  const lines = [];
  const platforms = Array.isArray(manifest?.platforms) ? manifest.platforms : [];

  lines.push("# Publish Report");
  lines.push("");
  lines.push(`- Generated at: ${formatLocalTimestamp()}`);
  lines.push(`- BookName: ${metadata.book_name || ""}`);
  lines.push(`- Language: ${metadata.language || ""}`);
  lines.push(`- Ready: ${manifest?.ready ? "Yes" : "No"}`);
  lines.push("");
  lines.push("## Book");
  lines.push("");
  lines.push(`- Title: ${metadata.title || ""}`);
  lines.push(`- Subtitle: ${metadata.subtitle || ""}`);
  lines.push(`- Author: ${metadata.author || ""}`);
  lines.push(`- Type: ${metadata.book_type || ""}`);
  lines.push(`- Publisher: ${metadata.publisher || ""}`);
  lines.push(`- Imprint: ${metadata.imprint || ""}`);
  lines.push(`- Rights: ${metadata.rights || ""}`);
  lines.push(`- Edition type: ${metadata.edition_type || ""}`);
  lines.push("");
  lines.push("## Discovery");
  lines.push("");
  lines.push(`- Keywords: ${(metadata.keywords || []).join(", ")}`);
  lines.push(`- Categories: ${(metadata.categories || []).join(", ")}`);
  lines.push(`- Formats: ${(metadata.formats || []).join(", ")}`);
  lines.push("");
  lines.push("## Platforms");
  lines.push("");

  if (!platforms.length) {
    lines.push("- None");
  } else {
    platforms.forEach((platform) => {
      lines.push(`### ${platform.name || ""}`);
      lines.push(`- Folder: ${platform.folder || ""}`);
      lines.push(`- Metadata: ${platform.metadata || ""}`);
      lines.push(`- EPUB: ${platform.copied_files?.epub || ""}`);
      lines.push(`- PDF: ${platform.copied_files?.pdf || ""}`);
      lines.push(`- DOCX: ${platform.copied_files?.docx || ""}`);
      lines.push(`- Cover: ${platform.copied_files?.cover || ""}`);
      lines.push("");
    });
  }

  return lines.join("\r\n");
}

function parsePublishMetadataMarkdown(markdown, existing = {}) {
  const raw = String(markdown || "").replace(/^\uFEFF/, "");
  const lines = raw.split(/\r?\n/);
  const rootFields = {};
  const rightsFields = {};
  const marketingFields = {};
  const selectedPlatformCategories = {
    amazon: existing.platform_selected_categories?.amazon || existing.discovery?.platform_selected_categories?.amazon || "",
    apple: existing.platform_selected_categories?.apple || existing.discovery?.platform_selected_categories?.apple || "",
    google: existing.platform_selected_categories?.google || existing.discovery?.platform_selected_categories?.google || ""
  };
  const recommendedCategories = JSON.parse(JSON.stringify(existing.platform_recommended_categories || existing.discovery?.platform_recommended_categories || {}));
  const rightsParagraph = [];
  const shortDescription = [];
  const longDescription = [];
  const backCoverBlurb = [];
  const authorBio = [];
  const keywords = [];
  const categories = [];
  const formats = [];
  let currentSection = "root";
  let currentPlatform = "";

  const getPlatformKey = (value) => {
    const normalized = String(value || "").trim().toLowerCase();
    if (normalized.includes("amazon")) return "amazon";
    if (normalized.includes("apple")) return "apple";
    if (normalized.includes("google")) return "google";
    return "";
  };

  const normalizeFieldKey = (key) => {
    const rawKey = String(key || "").trim().toLowerCase();
    const map = {
      "书名": "title",
      "title": "title",
      "副标题": "subtitle",
      "subtitle": "subtitle",
      "作者": "author",
      "author": "author",
      "语言": "language",
      "language": "language",
      "出版方": "publisher",
      "publisher": "publisher",
      "品牌": "imprint",
      "imprint": "imprint",
      "版本类型": "edition type",
      "edition type": "edition type",
      "发布日期": "publication date",
      "publication date": "publication date",
      "版权持有人": "copyright holder",
      "copyright holder": "copyright holder",
      "发行地区": "territory",
      "territory": "territory",
      "发行权利": "distribution rights",
      "distribution rights": "distribution rights",
      "宣传语": "tagline",
      "tagline": "tagline",
      "封面短句": "cover hook",
      "cover hook": "cover hook",
      "腰封文案": "obi copy",
      "obi copy": "obi copy",
      "书脊文案": "spine text",
      "spine text": "spine text",
      "默认分类": "selected default",
      "selected default": "selected default"
    };
    return map[rawKey] || rawKey;
  };

  const normalizeSectionHeading = (heading) => {
    const rawHeading = String(heading || "").trim().toLowerCase();
    const map = {
      "版权": "rights",
      "rights": "rights",
      "营销文案": "marketing",
      "marketing": "marketing",
      "短简介": "short_description",
      "short description": "short_description",
      "长简介": "long_description",
      "long description": "long_description",
      "封底摘要": "back_cover_blurb",
      "back cover blurb": "back_cover_blurb",
      "作者简介": "author_bio",
      "author bio": "author_bio",
      "关键词": "keywords",
      "keywords": "keywords",
      "分类": "categories",
      "categories": "categories",
      "平台推荐分类": "platform_recommended_categories",
      "platform recommended categories": "platform_recommended_categories",
      "格式": "formats",
      "formats": "formats"
    };
    return map[rawHeading] || rawHeading;
  };

  const parseFieldLine = (line) => {
    const match = String(line || "").trim().match(/^- ([^:]+):\s*(.*)$/);
    if (!match) {
      return null;
    }
    return { key: normalizeFieldKey(match[1].trim()), value: match[2].trim() };
  };

  const extractBulletSection = (sectionTitle) => {
    const targetHeading = `## ${String(sectionTitle || "").trim().toLowerCase()}`;
    let collecting = false;
    const results = [];

    for (const entry of lines) {
      const trimmedEntry = String(entry || "").trim();
      const normalizedHeading = trimmedEntry.toLowerCase();

      if (normalizedHeading === targetHeading) {
        collecting = true;
        continue;
      }

      if (collecting && /^##\s+/i.test(trimmedEntry)) {
        break;
      }

      if (collecting && trimmedEntry.startsWith("- ")) {
        results.push(trimmedEntry.replace(/^- /, "").trim());
      }
    }

    return results.filter(Boolean);
  };

  const pushParagraphLine = (bucket, line) => {
    const value = String(line || "").trimEnd();
    if (!bucket.length && !value.trim()) {
      return;
    }
    bucket.push(value);
  };

  for (const line of lines) {
    const trimmed = String(line || "").trim();

    if (/^###\s+/.test(trimmed)) {
      currentSection = "platform_recommended_categories";
      currentPlatform = getPlatformKey(trimmed.replace(/^###\s+/, ""));
      if (currentPlatform && !Array.isArray(recommendedCategories[currentPlatform])) {
        recommendedCategories[currentPlatform] = [];
      }
      continue;
    }

    if (/^##\s+/.test(trimmed)) {
      currentPlatform = "";
      const heading = normalizeSectionHeading(trimmed.replace(/^##\s+/, "").trim());
      if (heading === "rights") currentSection = "rights";
      else if (heading === "marketing") currentSection = "marketing";
      else if (heading === "short_description") currentSection = "short_description";
      else if (heading === "long_description") currentSection = "long_description";
      else if (heading === "back_cover_blurb") currentSection = "back_cover_blurb";
      else if (heading === "author_bio") currentSection = "author_bio";
      else if (heading === "keywords") currentSection = "keywords";
      else if (heading === "categories") currentSection = "categories";
      else if (heading === "platform_recommended_categories") currentSection = "platform_recommended_categories";
      else if (heading === "formats") currentSection = "formats";
      else currentSection = "other";
      continue;
    }

    if (/^#\s+/.test(trimmed)) {
      currentSection = "root";
      currentPlatform = "";
      continue;
    }

    if (currentSection === "root") {
      const field = parseFieldLine(trimmed);
      if (field) rootFields[field.key] = field.value;
      continue;
    }

    if (currentSection === "rights") {
      const field = parseFieldLine(trimmed);
      if (field) rightsFields[field.key] = field.value;
      else pushParagraphLine(rightsParagraph, line);
      continue;
    }

    if (currentSection === "marketing") {
      const field = parseFieldLine(trimmed);
      if (field) marketingFields[field.key] = field.value;
      continue;
    }

    if (currentSection === "short_description") {
      pushParagraphLine(shortDescription, line);
      continue;
    }

    if (currentSection === "long_description") {
      pushParagraphLine(longDescription, line);
      continue;
    }

    if (currentSection === "back_cover_blurb") {
      pushParagraphLine(backCoverBlurb, line);
      continue;
    }

    if (currentSection === "author_bio") {
      pushParagraphLine(authorBio, line);
      continue;
    }

    if (currentSection === "keywords" && trimmed.startsWith("- ")) {
      keywords.push(trimmed.replace(/^- /, "").trim());
      continue;
    }

    if (currentSection === "categories" && trimmed.startsWith("- ")) {
      categories.push(trimmed.replace(/^- /, "").trim());
      continue;
    }

    if (currentSection === "formats" && trimmed.startsWith("- ")) {
      formats.push(trimmed.replace(/^- /, "").trim());
      continue;
    }

    if (currentSection === "platform_recommended_categories" && currentPlatform) {
      const selectedMatch = trimmed.match(/^- Selected default:\s*(.*)$/i);
      if (selectedMatch) {
        selectedPlatformCategories[currentPlatform] = selectedMatch[1].trim();
        continue;
      }

      const recMatch = trimmed.match(/^- \[(.*?)\]\s+(.*?)\s+-\s+(.*)$/);
      if (recMatch) {
        recommendedCategories[currentPlatform] = recommendedCategories[currentPlatform] || [];
        recommendedCategories[currentPlatform].push({
          priority: recMatch[1].trim(),
          path: recMatch[2].trim(),
          note: recMatch[3].trim()
        });
      }
    }
  }

  const cleanBlock = (bucket, fallback = "") => {
    const text = bucket.join("\n").replace(/^\s+|\s+$/g, "");
    return text || fallback || "";
  };

  const languageMatch = String(rootFields.language || "").match(/^([a-z]{2,5})\s*(?:\((.*?)\))?$/i);

  return {
    title: sanitizeText(rootFields.title || existing.title),
    subtitle: sanitizeText(rootFields.subtitle || existing.subtitle),
    author: sanitizeText(rootFields.author || existing.author),
    language: sanitizeText((languageMatch?.[1] || existing.language || "").toLowerCase()),
    language_name: sanitizeText(languageMatch?.[2] || existing.language_name),
    publisher: sanitizeText(rootFields.publisher || existing.publisher),
    imprint: sanitizeText(rootFields.imprint || existing.imprint),
    edition_type: sanitizeText(rootFields["edition type"] || existing.edition_type),
    publication_date: sanitizeText(rootFields["publication date"] || existing.publication_date),
    rights: sanitizeText(cleanBlock(rightsParagraph, existing.rights)),
    copyright_holder: sanitizeText(rightsFields["copyright holder"] || existing.copyright_holder),
    territory: sanitizeText(rightsFields.territory || existing.territory),
    distribution_rights: sanitizeText(rightsFields["distribution rights"] || existing.distribution_rights),
    marketing_tagline: sanitizeText(marketingFields.tagline || existing.marketing_tagline),
    cover_hook: sanitizeText(marketingFields["cover hook"] || existing.cover_hook),
    obi_copy: sanitizeText(marketingFields["obi copy"] || existing.obi_copy),
    spine_text: sanitizeText(marketingFields["spine text"] || existing.spine_text),
    short_description: sanitizeText(cleanBlock(shortDescription, existing.short_description)),
    long_description: sanitizeText(cleanBlock(longDescription, existing.long_description)),
    back_cover_blurb: sanitizeText(cleanBlock(backCoverBlurb, existing.back_cover_blurb)),
    author_bio: sanitizeText(cleanBlock(authorBio, existing.author_bio)),
    keywords: sanitizeList(keywords.length ? keywords : (extractBulletSection("Keywords").length ? extractBulletSection("Keywords") : (existing.keywords || existing.discovery?.keywords))),
    categories: sanitizeList(categories.length ? categories : (extractBulletSection("Categories").length ? extractBulletSection("Categories") : (existing.categories || existing.discovery?.categories))),
    formats: sanitizeList(formats.length ? formats : (extractBulletSection("Formats").length ? extractBulletSection("Formats") : existing.formats)),
    platform_selected_categories: {
      amazon: sanitizeText(selectedPlatformCategories.amazon),
      apple: sanitizeText(selectedPlatformCategories.apple),
      google: sanitizeText(selectedPlatformCategories.google)
    },
    platform_recommended_categories: recommendedCategories
  };
}

function extractMarkdownBulletSection(markdown, sectionTitle) {
  const lines = String(markdown || "").replace(/^\uFEFF/, "").split(/\r?\n/);
  const targetHeading = `## ${String(sectionTitle || "").trim().toLowerCase()}`;
  let collecting = false;
  const results = [];

  for (const line of lines) {
    const trimmed = String(line || "").trim();
    const normalized = trimmed.toLowerCase();

    if (normalized === targetHeading) {
      collecting = true;
      continue;
    }

    if (collecting && /^##\s+/i.test(trimmed)) {
      break;
    }

    if (collecting && trimmed.startsWith("- ")) {
      results.push(trimmed.replace(/^- /, "").trim());
    }
  }

  return results.filter(Boolean);
}

function buildPlatformMetadataFromPublish(metadata, platformName) {
  return {
    platform: platformName,
    book_name: metadata.book_name || "",
    language: metadata.language || "",
    language_name: metadata.language_name || "",
    title: metadata.title || "",
    subtitle: metadata.subtitle || "",
    author: metadata.author || "",
    audience: metadata.audience || "",
    type: metadata.book_type || "",
    style: metadata.style || "",
    publisher: metadata.publisher || "",
    imprint: metadata.imprint || "",
    publication_date: metadata.publication_date || "",
    rights: metadata.rights || "",
    copyright_holder: metadata.copyright_holder || "",
    copyright_year: String(metadata.copyright_year || ""),
    territory: metadata.territory || "",
    distribution_rights: metadata.distribution_rights || "",
    edition_type: metadata.edition_type || "",
    short_description: metadata.short_description || "",
    long_description: metadata.long_description || "",
    marketing_tagline: metadata.marketing_tagline || "",
    cover_hook: metadata.cover_hook || "",
    back_cover_blurb: metadata.back_cover_blurb || "",
    obi_copy: metadata.obi_copy || "",
    author_bio: metadata.author_bio || "",
    spine_text: metadata.spine_text || "",
    keywords: Array.isArray(metadata.keywords) ? metadata.keywords : [],
    categories: Array.isArray(metadata.categories) ? metadata.categories : [],
    platform_recommended_categories: metadata.platform_recommended_categories || {},
    platform_selected_categories: metadata.platform_selected_categories || {},
    formats: Array.isArray(metadata.formats) ? metadata.formats : [],
    identification: metadata.identification || {},
    marketing: metadata.marketing || {},
    rights_metadata: metadata.rights_metadata || {},
    discovery: metadata.discovery || {},
    distribution: metadata.distribution || {},
    source_files: {
      epub: metadata.source_files?.epub || "",
      pdf: metadata.source_files?.pdf || "",
      docx: metadata.source_files?.docx || "",
      cover: metadata.source_files?.cover || ""
    }
  };
}

function runEngineScriptSync(scriptName, args = []) {
  const scriptPath = path.join(ENGINE_ROOT, scriptName);
  const psArgs = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath,
    ...args
  ];

  const result = spawnSync("powershell.exe", psArgs, {
    cwd: ENGINE_ROOT,
    env: getChildProcessEnv(),
    encoding: "utf8"
  });

  if ((result.status ?? -1) !== 0) {
    const message = [result.stderr, result.stdout]
      .filter(Boolean)
      .join("\n")
      .trim() || `${scriptName} failed.`;
    throw new Error(message);
  }

  return result;
}

function makeHealthCheck(id, label, status, message, details = {}) {
  return {
    id,
    label,
    status,
    message,
    details
  };
}

function runCommandHealthCheck({ id, label, command, args = [], required = true, parseVersion = null }) {
  try {
    const result = spawnSync(command, args, {
      cwd: ENGINE_ROOT,
      env: getChildProcessEnv(),
      encoding: "utf8",
      timeout: 5000,
      windowsHide: true,
      maxBuffer: 1024 * 1024
    });

    if (result.error) {
      return makeHealthCheck(
        id,
        label,
        required ? "fail" : "warn",
        result.error.code === "ENOENT" ? `${label} 未安装或不在 PATH 中。` : `${label} 检查失败：${result.error.message}`,
        { command }
      );
    }

    const output = `${result.stdout || ""}${result.stderr || ""}`.trim();
    if ((result.status ?? -1) !== 0) {
      return makeHealthCheck(
        id,
        label,
        required ? "fail" : "warn",
        `${label} 命令返回非 0 状态：${result.status}`,
        { command, exitCode: result.status, output: output.slice(0, 600) }
      );
    }

    const version = parseVersion ? parseVersion(output) : output.split(/\r?\n/)[0] || "available";
    return makeHealthCheck(id, label, "pass", `${label} 可用。`, { command, version });
  } catch (error) {
    return makeHealthCheck(id, label, required ? "fail" : "warn", `${label} 检查异常：${error.message}`, { command });
  }
}

function checkWorkspaceRootHealth() {
  const workspaceParentRoot = getWorkspaceParentRoot();
  const showServerPaths = canCurrentUserSeeServerPaths();
  const details = {
    workspaceParentRoot,
    currentUser: getUserPublic(getCurrentUserContext())
  };
  if (showServerPaths) {
    details.globalWorkspaceParentRoot = WORKSPACE_PARENT_ROOT;
  }
  if (!fs.existsSync(workspaceParentRoot)) {
    return makeHealthCheck("workspaceRoot", "工作区根目录", "fail", "工作区根目录不存在。", details);
  }
  if (!fs.statSync(workspaceParentRoot).isDirectory()) {
    return makeHealthCheck("workspaceRoot", "工作区根目录", "fail", "工作区根目录不是文件夹。", details);
  }

  const probePath = path.join(workspaceParentRoot, `.sagewrite-health-${process.pid}-${Date.now()}.tmp`);
  try {
    fs.writeFileSync(probePath, "ok", "utf8");
    fs.readFileSync(probePath, "utf8");
    fs.unlinkSync(probePath);
    return makeHealthCheck("workspaceRoot", "工作区根目录", "pass", "工作区根目录可读写。", details);
  } catch (error) {
    try {
      if (fs.existsSync(probePath)) {
        fs.unlinkSync(probePath);
      }
    } catch {
      // ignore cleanup failure
    }
    return makeHealthCheck("workspaceRoot", "工作区根目录", "fail", `工作区根目录不可读写：${error.message}`, details);
  }
}

function buildSystemHealthReport() {
  const showServerPaths = canCurrentUserSeeServerPaths();
  const checks = [];
  checks.push(makeHealthCheck("mode", "运行模式", "pass", `当前模式：${APP_MODE}`, {
    host: HOST,
    port: PORT,
    appMode: APP_MODE
  }));
  checks.push(makeHealthCheck("node", "Node.js", "pass", "Node.js 可用。", {
    version: process.version,
    executable: process.execPath
  }));
  checks.push(runCommandHealthCheck({
    id: "powershell",
    label: "PowerShell",
    command: "powershell.exe",
    args: ["-NoProfile", "-Command", "$PSVersionTable.PSVersion.ToString()"]
  }));
  checks.push(runCommandHealthCheck({
    id: "imagemagick",
    label: "ImageMagick",
    command: "magick.exe",
    args: ["-version"],
    parseVersion: (output) => output.split(/\r?\n/).find((line) => line.toLowerCase().startsWith("version:")) || output.split(/\r?\n/)[0] || "available"
  }));
  checks.push(runCommandHealthCheck({
    id: "pandoc",
    label: "Pandoc",
    command: "pandoc.exe",
    args: ["--version"],
    parseVersion: (output) => output.split(/\r?\n/)[0] || "available"
  }));
  checks.push(makeHealthCheck(
    "openaiKey",
    "OPENAI_API_KEY",
    process.env.OPENAI_API_KEY ? "pass" : "warn",
    process.env.OPENAI_API_KEY ? "OPENAI_API_KEY 已配置。" : "OPENAI_API_KEY 未配置；LLM 写作、检查和图像识别步骤会失败。",
    { configured: Boolean(process.env.OPENAI_API_KEY) }
  ));
  checks.push(makeHealthCheck(
    "auth",
    "登录保护",
    APP_MODE === "cloud" && !isAuthEnabled() ? "warn" : "pass",
    APP_MODE === "cloud" && !isAuthEnabled()
      ? "当前是 cloud 模式但未启用登录保护；对外开放前必须配置 SAGEWRITE_AUTH=password 或 SAGEWRITE_AUTH=users。"
      : isUserAuthEnabled() ? "多用户账号登录已启用。" : isAuthEnabled() ? "密码登录已启用。" : "本地模式未启用登录保护。",
    showServerPaths ? getAuthDetails() : getPublicAuthDetails()
  ));
  if (isUserAuthEnabled()) {
    const store = ensureUserStore();
    checks.push(makeHealthCheck(
      "userStore",
      "用户库",
      store && store.users.length ? "pass" : "fail",
      store && store.users.length
        ? `用户库可用，当前有 ${store.users.length} 个用户。`
        : "用户库不存在或没有用户；设置 SAGEWRITE_ADMIN_PASSWORD 后重启可自动创建 admin 用户。",
      showServerPaths
        ? { userStorePath: USER_STORE_PATH, userCount: store?.users?.length || 0 }
        : { userCount: store?.users?.length || 0 }
    ));
  }
  checks.push(checkWorkspaceRootHealth());

  const failCount = checks.filter((item) => item.status === "fail").length;
  const warnCount = checks.filter((item) => item.status === "warn").length;
  const summary = failCount ? "fail" : warnCount ? "warn" : "pass";
  return {
    generatedAt: formatLocalTimestamp(),
    appMode: APP_MODE,
    summary,
    failCount,
    warnCount,
    passCount: checks.filter((item) => item.status === "pass").length,
    checks
  };
}

function syncPublishMetadataFiles(bookRoot, languageCode, nextMetadata) {
  const publishRoot = getPublishLanguageRoot(bookRoot, languageCode);
  const metadataJsonPath = path.join(publishRoot, "publish_metadata.json");
  const metadataMdPath = path.join(publishRoot, "publish_metadata.md");
  const manifestPath = path.join(publishRoot, "publish_manifest.json");
  const reportPath = path.join(publishRoot, "publish_report.md");

  writeJsonFile(metadataJsonPath, nextMetadata);
  fs.writeFileSync(metadataMdPath, buildPublishMetadataMarkdown(nextMetadata), "utf8");

  const manifest = readJsonFileSafe(manifestPath);
  fs.writeFileSync(reportPath, buildPublishReportMarkdown(nextMetadata, manifest), "utf8");

  const platformScripts = {
    amazon: "09c-amazon.ps1",
    apple: "09d-apple.ps1",
    google: "09e-google.ps1"
  };

  Object.entries(platformScripts).forEach(([platformName, scriptName]) => {
    const platformRoot = path.join(publishRoot, platformName);
    if (!fs.existsSync(platformRoot)) {
      return;
    }

    const platformMetadataPath = path.join(platformRoot, "metadata.json");
    writeJsonFile(platformMetadataPath, buildPlatformMetadataFromPublish(nextMetadata, platformName));
    runEngineScriptSync(scriptName, [
      "-BookName", nextMetadata.book_name || "",
      "-Language", languageCode,
      "-Force"
    ]);
  });
}

function buildCoverCopyMarkdown(copyData) {
  const selected = copyData?.selected || {};
  const candidates = copyData?.candidates || {};
  const editorNotes = Array.isArray(copyData?.editor_notes) ? copyData.editor_notes : [];

  const lines = [];
  lines.push("# Cover Copy");
  lines.push("");
  lines.push("## Selected");
  lines.push("");
  lines.push(`- Subtitle: ${selected.subtitle || ""}`);
  lines.push(`- Back cover hook: ${selected.back_cover_hook || ""}`);
  lines.push(`- Obi copy: ${selected.obi_copy || ""}`);
  lines.push(`- Marketing tagline: ${selected.marketing_tagline || ""}`);
  lines.push(`- Spine text: ${selected.spine_text || ""}`);
  lines.push("");
  lines.push("## Back Cover Blurb");
  lines.push("");
  lines.push(selected.back_cover_blurb || "");
  lines.push("");
  lines.push("## Author Bio");
  lines.push("");
  lines.push(selected.author_bio || "");
  lines.push("");
  lines.push("## Candidate Pools");
  lines.push("");

  [
    ["Subtitle", candidates.subtitle || []],
    ["Back Cover Hook", candidates.back_cover_hook || []],
    ["Obi Copy", candidates.obi_copy || []],
    ["Marketing Tagline", candidates.marketing_tagline || []]
  ].forEach(([title, items]) => {
    lines.push(`### ${title}`);
    if (Array.isArray(items) && items.length) {
      items.forEach((item) => lines.push(`- ${item}`));
    } else {
      lines.push("- ");
    }
    lines.push("");
  });

  lines.push("## Editor Notes");
  if (editorNotes.length) {
    editorNotes.forEach((item) => lines.push(`- ${item}`));
  } else {
    lines.push("- ");
  }

  return lines.join("\r\n");
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store"
  });
  res.end(JSON.stringify(payload));
}

function sendText(res, statusCode, text, type = "text/plain; charset=utf-8") {
  res.writeHead(statusCode, {
    "Content-Type": type,
    "Cache-Control": "no-store"
  });
  res.end(text);
}

function sanitizeJobNamePart(value, fallback = "run") {
  const clean = String(value || fallback).replace(/[^a-zA-Z0-9._-]+/g, "_").replace(/^_+|_+$/g, "");
  return clean || fallback;
}

function serializeJob(job, { includeOutput = true } = {}) {
  if (!job) {
    return null;
  }
  const payload = {
    id: job.id,
    status: job.status,
    createdAt: job.createdAt,
    updatedAt: job.updatedAt,
    timestamp: job.timestamp,
    exitCode: job.exitCode,
    childPid: job.childPid || null,
    archived: Boolean(job.archived),
    appMode: APP_MODE,
    meta: job.meta || {}
  };
  if (includeOutput) {
    payload.output = job.output || "";
  }
  return payload;
}

function persistJobState(job) {
  const statePath = job?.meta?.statePath;
  if (!statePath) {
    return;
  }
  try {
    const bookName = job.meta?.bookName;
    if (bookName) {
      const paths = getWorkspacePaths(bookName, job.meta?.workspaceParentRoot || getWorkspaceParentRoot());
      if (!isPathInside(paths.webJobRoot, statePath)) {
        throw new Error("Job state path is outside webui-jobs.");
      }
    }
    ensureDir(path.dirname(statePath));
    fs.writeFileSync(statePath, `${JSON.stringify(serializeJob(job, { includeOutput: false }), null, 2)}\n`, "utf8");
  } catch (error) {
    job.output += `\n[webui-state-error] ${error.message}\n`;
  }
}

function appendJobOutputFile(job, chunk) {
  const outputPath = job?.meta?.outputPath;
  if (!outputPath || !chunk) {
    return;
  }
  try {
    const bookName = job.meta?.bookName;
    if (bookName) {
      const paths = getWorkspacePaths(bookName, job.meta?.workspaceParentRoot || getWorkspaceParentRoot());
      if (!isPathInside(paths.webRunRoot, outputPath)) {
        throw new Error("Job output path is outside webui-runs.");
      }
    }
    ensureDir(path.dirname(outputPath));
    fs.appendFileSync(outputPath, chunk, "utf8");
  } catch (error) {
    job.output += `\n[webui-log-error] ${error.message}\n`;
  }
}

function initializeJobPersistence(job, createdDate = new Date()) {
  const bookName = job.meta?.bookName;
  if (!bookName) {
    return;
  }

  try {
    const paths = getWorkspacePaths(bookName, job.meta?.workspaceParentRoot || getWorkspaceParentRoot());
    ensureDir(paths.webRunRoot);
    ensureDir(paths.webJobRoot);
    const route = sanitizeJobNamePart(job.meta?.route);
    const stamp = formatFileStamp(createdDate);
    const outputFileName = `${stamp}-${route}-${job.id}.log`;
    const stateFileName = `${stamp}-${route}-${job.id}.json`;
    const outputPath = resolveInside(paths.webRunRoot, outputFileName);
    const statePath = resolveInside(paths.webJobRoot, stateFileName);
    fs.writeFileSync(outputPath, "", "utf8");
    job.meta.outputFileName = outputFileName;
    job.meta.outputPath = outputPath;
    job.meta.stateFileName = stateFileName;
    job.meta.statePath = statePath;
    persistJobState(job);
  } catch (error) {
    job.output += `\n[webui-persistence-error] ${error.message}\n`;
  }
}

function jobStateToRunEntry(jobState) {
  const meta = jobState?.meta || {};
  return {
    source: "webui",
    timestamp: jobState.timestamp || formatLocalTimestamp(new Date(jobState.createdAt || Date.now())),
    step: meta.route || "webui",
    state: jobState.status || "unknown",
    message: jobState.status === "running"
      ? `Web UI ${meta.route || "task"} running. Job ID: ${jobState.id}.`
      : `Web UI ${meta.route || "task"} ${jobState.status || "unknown"}. Job ID: ${jobState.id}.`,
    data: {
      jobId: jobState.id,
      childPid: jobState.childPid || null,
      outputFileName: meta.outputFileName || "",
      outputPath: meta.outputPath || "",
      stateFileName: meta.stateFileName || "",
      statePath: meta.statePath || ""
    }
  };
}

function readRunningWebJobs(webJobRoot) {
  if (!fs.existsSync(webJobRoot)) {
    return [];
  }
  return fs.readdirSync(webJobRoot, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.toLowerCase().endsWith(".json"))
    .map((entry) => {
      try {
        return readJsonFile(path.join(webJobRoot, entry.name));
      } catch {
        return null;
      }
    })
    .filter((jobState) => jobState?.status === "running" && jobs.has(jobState.id))
    .map(jobStateToRunEntry);
}

function findRunningJob(bookName) {
  const currentUserId = getCurrentUserContext().id;
  const matches = Array.from(jobs.values())
    .filter((job) => job.status === "running" &&
      (!isUserAuthEnabled() || job.meta?.userId === currentUserId) &&
      (!bookName || job.meta?.bookName === bookName))
    .sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));
  return matches[matches.length - 1] || null;
}

function doesJobBelongToCurrentUser(job) {
  if (!job || !isUserAuthEnabled()) {
    return true;
  }
  return job.meta?.userId === getCurrentUserContext().id;
}

function readPersistedJobById(jobId, bookName = "") {
  if (!jobId) {
    return null;
  }
  const workspaceParentRoot = getWorkspaceParentRoot();
  const workspaceNames = bookName
    ? [`workspace-${bookName}`]
    : fs.existsSync(workspaceParentRoot)
      ? fs.readdirSync(workspaceParentRoot).filter((name) => name.startsWith("workspace-"))
      : [];

  for (const workspaceName of workspaceNames) {
    const currentBookName = workspaceName.replace(/^workspace-/, "");
    try {
      const paths = getWorkspacePaths(currentBookName);
      if (!fs.existsSync(paths.webJobRoot)) {
        continue;
      }
      const match = fs.readdirSync(paths.webJobRoot)
        .find((fileName) => fileName.endsWith(`${jobId}.json`) || fileName.includes(`-${jobId}.json`));
      if (!match) {
        continue;
      }
      const jobState = readJsonFile(path.join(paths.webJobRoot, match));
      const outputPath = jobState?.meta?.outputPath || "";
      const output = outputPath && isPathInside(paths.webRunRoot, outputPath) && fs.existsSync(outputPath)
        ? fs.readFileSync(outputPath, "utf8")
        : "";
      if (jobState.status === "running" && !jobs.has(jobId)) {
        return {
          ...jobState,
          status: "lost",
          exitCode: -2,
          output: `${output}\n[webui] This job was running, but the current server process is no longer tracking it. Check the archived log file and rerun if needed.\n`
        };
      }
      return { ...jobState, output };
    } catch {
      continue;
    }
  }
  return null;
}

function getMimeTypeByPath(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return {
    ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    ".epub": "application/epub+zip",
    ".html": "text/html; charset=utf-8",
    ".jpeg": "image/jpeg",
    ".jpg": "image/jpeg",
    ".json": "application/json; charset=utf-8",
    ".md": "text/markdown; charset=utf-8",
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".txt": "text/plain; charset=utf-8",
    ".webp": "image/webp"
  }[ext] || "application/octet-stream";
}

function safeHeaderFileName(filePath) {
  const baseName = path.basename(filePath).replace(/[\r\n]/g, "");
  return baseName.replace(/["\\]/g, "_").replace(/[^\x20-\x7E]/g, "_") || "download";
}

function encodedHeaderFileName(filePath) {
  return encodeURIComponent(path.basename(filePath).replace(/[\r\n]/g, ""));
}

function contentDispositionHeader(filePath, disposition = "attachment") {
  return `${disposition}; filename="${safeHeaderFileName(filePath)}"; filename*=UTF-8''${encodedHeaderFileName(filePath)}`;
}

function sendDiskFile(res, filePath, disposition = "attachment") {
  res.writeHead(200, {
    "Content-Type": getMimeTypeByPath(filePath),
    "Cache-Control": "no-store",
    "Content-Disposition": contentDispositionHeader(filePath, disposition)
  });
  res.end(fs.readFileSync(filePath));
}

function withQuery(pathname, params) {
  const search = new URLSearchParams();
  Object.entries(params || {}).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== "") {
      search.set(key, String(value));
    }
  });
  return `${pathname}?${search.toString()}`;
}

function cloudFilePayload(extra, targetPath, downloadUrl) {
  return {
    ...extra,
    opened: false,
    cloudMode: true,
    mode: APP_MODE,
    path: targetPath,
    downloadUrl,
    message: "云端模式不会打开服务器桌面；请使用浏览器下载/预览链接。"
  };
}

function cloudFolderPayload(extra, targetFolder) {
  return {
    ...extra,
    opened: false,
    cloudMode: true,
    mode: APP_MODE,
    path: targetFolder,
    message: "云端模式不会打开服务器资源管理器；请使用页面中的文件列表、下载或预览功能。"
  };
}

function readJsonBody(req, maxBytes = 5_000_000) {
  return new Promise((resolve, reject) => {
    let raw = "";
    let size = 0;
    req.on("data", (chunk) => {
      size += chunk.length;
      raw += chunk;
      if (size > maxBytes) {
        reject(new Error("Request body too large."));
      }
    });
    req.on("end", () => {
      if (!raw.trim()) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error("Invalid JSON body."));
      }
    });
    req.on("error", reject);
  });
}

function listWorkspacesFromRoot(workspaceParentRoot = getWorkspaceParentRoot()) {
  if (!fs.existsSync(workspaceParentRoot)) {
    return [];
  }

  return fs.readdirSync(workspaceParentRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.startsWith("workspace-"))
    .map((entry) => {
      const bookName = entry.name.replace(/^workspace-/, "");
      const workspacePath = path.join(workspaceParentRoot, entry.name);
      const bookRoot = path.join(workspacePath, "sagewrite", "book");
      const projectMetadata = getProjectMetadataForPaths(bookName, { workspacePath, bookRoot });
      if (!canUserAccessProjectMetadata(getCurrentUserContext(), projectMetadata)) {
        return null;
      }
      const objectivePath = path.join(bookRoot, "00_brief", "objective.md");
      const tocPath = path.join(bookRoot, "01_outline", "toc.md");
      const toc2Path = path.join(bookRoot, "01_outline", "toc2.md");
      const chapterRoot = path.join(bookRoot, "02_chapters");
      const outputRoot = path.join(bookRoot, "04_output");
      const publishRoot = path.join(bookRoot, "09_publish");
      const logRoot = path.join(bookRoot, "logs");
      const statusPath = path.join(logRoot, "status.json");
      const runLogPath = path.join(logRoot, "run_history.jsonl");
      const webRunIndexPath = path.join(logRoot, "webui_runs.jsonl");
      const webJobRoot = path.join(logRoot, "webui-jobs");
      const editReportJsonPath = path.join(logRoot, "edit_report.json");
      const coverArtifacts = getCoverArtifacts(bookRoot);
      const objectiveContent = fs.existsSync(objectivePath)
        ? fs.readFileSync(objectivePath, "utf8").replace(/^\uFEFF/, "")
        : "";
      const tocContent = fs.existsSync(tocPath)
        ? fs.readFileSync(tocPath, "utf8")
        : "";
      const chapterFiles = getChapterMetadata(chapterRoot);
      const chapterCount = chapterFiles.length;
      const outputs = listOutputDocuments(outputRoot);
      const outputLanguages = getOutputLanguages(bookRoot);
      const publishLanguages = listDirectories(publishRoot);
      let status = null;
      let recentRuns = [];
      let webRuns = [];
      let runningWebJobs = [];
      let editReport = null;
      const objectiveData = parseFrontMatterMarkdown(objectivePath) || null;

      if (fs.existsSync(statusPath)) {
        try {
          status = readJsonFile(statusPath);
        } catch {
          status = {
            last_error: { message: "status.json unreadable" }
          };
        }
      }

      if (fs.existsSync(runLogPath)) {
        recentRuns = readJsonLines(runLogPath);
      }

      if (fs.existsSync(webRunIndexPath)) {
        webRuns = readJsonLines(webRunIndexPath);
      }

      runningWebJobs = readRunningWebJobs(webJobRoot);

      if (fs.existsSync(editReportJsonPath)) {
        try {
          editReport = readJsonFile(editReportJsonPath);
        } catch {
          editReport = {
            error: "edit_report.json unreadable"
          };
        }
      }

      const mergedRuns = [...recentRuns, ...webRuns, ...runningWebJobs]
        .sort((a, b) => String(a.timestamp || "").localeCompare(String(b.timestamp || "")))
        .slice(-8);

      return {
        projectKey: `${projectMetadata.tenantId}:${bookName}`,
        bookName,
        workspacePath,
        hasObjective: fs.existsSync(objectivePath),
        objectiveData,
        objectiveContent,
        objectiveRelativePath: "00_brief/objective.md",
        objectivePath,
        hasToc: fs.existsSync(tocPath),
        hasExpandedToc: fs.existsSync(toc2Path),
        tocContent,
        chapterFiles,
        chapterCount,
        outputFiles: outputs,
        outputLanguages,
        publishLanguages,
        project: getProjectPublicMetadata(projectMetadata),
        coverArtifacts,
        status,
        recentRuns: mergedRuns,
        editReport
      };
    })
    .filter(Boolean)
    .sort((a, b) => a.bookName.localeCompare(b.bookName, "zh-Hans-CN"));
}

function listWorkspaces() {
  return listWorkspacesFromRoot(getWorkspaceParentRoot());
}

function getProjectManagementRootsForActor(actor = getCurrentUserContext()) {
  if (!isUserAuthEnabled()) {
    return [WORKSPACE_PARENT_ROOT];
  }
  if (!isPlatformAdmin(actor)) {
    return [getUserWorkspaceRoot(actor)];
  }

  const roots = new Set([path.resolve(WORKSPACE_PARENT_ROOT)]);
  const store = ensureUserStore();
  (store?.tenants || []).forEach((tenant) => {
    roots.add(path.resolve(getTenantWorkspaceRoot(tenant.id)));
  });
  if (fs.existsSync(USER_WORKSPACE_ROOT)) {
    fs.readdirSync(USER_WORKSPACE_ROOT, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .forEach((entry) => roots.add(path.resolve(path.join(USER_WORKSPACE_ROOT, entry.name))));
  }
  return Array.from(roots);
}

function listProjectsForActor(actor = getCurrentUserContext()) {
  const seen = new Set();
  return getProjectManagementRootsForActor(actor)
    .flatMap((root) => listWorkspacesFromRoot(root))
    .filter((item) => {
      const key = `${item.project?.tenantId || ""}:${item.bookName}:${path.resolve(item.workspacePath || "")}`;
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    })
    .sort((a, b) => {
      const tenantCompare = String(a.project?.tenantName || a.project?.tenantId || "")
        .localeCompare(String(b.project?.tenantName || b.project?.tenantId || ""), "zh-Hans-CN");
      return tenantCompare || a.bookName.localeCompare(b.bookName, "zh-Hans-CN");
    });
}

function getAssignableAuthorsForActor(actor, store = ensureUserStore()) {
  if (!store || !actor) {
    return [];
  }
  const role = getRoleId(actor.role);
  if (isPlatformAdmin(actor)) {
    return (store.users || []).filter((user) => getRoleId(user.role) === "author" && !user.disabled);
  }
  if (role === "tenant_admin") {
    const tenantId = getTenantIdFromUser(actor);
    return (store.users || []).filter((user) =>
      getRoleId(user.role) === "author" &&
      !user.disabled &&
      getTenantIdFromUser(user) === tenantId
    );
  }
  if (role === "editor") {
    const managedAuthorIds = getManagedAuthorIdsForEditor(actor);
    return (store.users || []).filter((user) => managedAuthorIds.has(String(user.id || "")) && !user.disabled);
  }
  if (role === "author") {
    const author = findUserById(actor.id, store) || actor;
    return author && !author.disabled ? [author] : [];
  }
  return [];
}

function getProjectUserOptionPublic(user) {
  const publicUser = getUserPublic(user);
  return publicUser ? {
    id: publicUser.id,
    username: publicUser.username,
    displayName: publicUser.displayName,
    role: publicUser.role,
    roleId: publicUser.roleId,
    tenantId: publicUser.tenantId,
    tenantName: publicUser.tenantName,
    managerUserId: publicUser.managerUserId || "",
    managerUsername: publicUser.managerUsername || ""
  } : null;
}

function findActiveProjectUser(userId, { role, tenantId, store = ensureUserStore() } = {}) {
  const cleanUserId = String(userId || "").trim();
  if (!cleanUserId) {
    return null;
  }
  const user = findUserById(cleanUserId, store);
  if (!user || user.disabled) {
    throw new Error("Assigned project user must be active.");
  }
  if (role && getRoleId(user.role) !== role) {
    throw new Error(`Assigned project user must be ${role}.`);
  }
  if (tenantId && getTenantIdFromUser(user) !== normalizeTenantId(tenantId)) {
    throw new Error("Assigned project user must be in the same tenant.");
  }
  return user;
}

function findProjectForActor(bookName, tenantId = "", actor = getCurrentUserContext()) {
  validateBookName(bookName);
  const normalizedTenantId = tenantId ? normalizeTenantId(tenantId) : "";
  for (const root of getProjectManagementRootsForActor(actor)) {
    const workspacePath = path.join(root, `workspace-${bookName}`);
    if (!fs.existsSync(workspacePath)) {
      continue;
    }
    const paths = getWorkspacePaths(bookName, root);
    const metadata = getProjectMetadataForPaths(bookName, paths);
    if (normalizedTenantId && normalizeTenantId(metadata.tenantId) !== normalizedTenantId) {
      continue;
    }
    if (canUserAccessProjectMetadata(actor, metadata)) {
      return { paths, metadata };
    }
  }
  return null;
}

function assertCurrentUserCanManageProjects() {
  const user = getCurrentUserContext();
  if (!user || !canManageCompanyProjects(user)) {
    throw new Error("Project management permission is required.");
  }
  return user;
}

function updateProjectMetadataForActor({ bookName, tenantId = "", authorUserId = undefined, editorUserId = undefined }, actor = getCurrentUserContext()) {
  if (!canManageCompanyProjects(actor)) {
    throw new Error("Project management permission is required.");
  }
  const found = findProjectForActor(bookName, tenantId, actor);
  if (!found) {
    throw new Error("Project not found.");
  }

  const { paths, metadata } = found;
  const projectTenantId = normalizeTenantId(metadata.tenantId);
  if (!isPlatformAdmin(actor) && projectTenantId !== getTenantIdFromUser(actor)) {
    throw new Error("You can only manage projects in your own tenant.");
  }

  const store = ensureUserStore();
  const nextMetadata = {
    version: 1,
    bookName,
    tenantId: projectTenantId,
    tenantName: metadata.tenantName || getProjectTenantName(projectTenantId),
    ownerUserId: metadata.ownerUserId || metadata.createdByUserId || actor.id || "",
    ownerUsername: metadata.ownerUsername || metadata.createdByUsername || actor.username || "",
    ownerDisplayName: metadata.ownerDisplayName || actor.displayName || "",
    authorUserId: metadata.authorUserId || "",
    authorUsername: metadata.authorUsername || "",
    editorUserId: metadata.editorUserId || "",
    editorUsername: metadata.editorUsername || "",
    createdByUserId: metadata.createdByUserId || actor.id || "",
    createdByUsername: metadata.createdByUsername || actor.username || "",
    createdAt: metadata.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    workspaceRoot: getWorkspaceParentRootFromPaths(paths)
  };

  if (authorUserId !== undefined) {
    const author = findActiveProjectUser(authorUserId, { role: "author", tenantId: projectTenantId, store });
    nextMetadata.authorUserId = author?.id || "";
    nextMetadata.authorUsername = author?.username || "";
    if (author) {
      nextMetadata.ownerUserId = author.id || "";
      nextMetadata.ownerUsername = author.username || "";
      nextMetadata.ownerDisplayName = author.displayName || author.username || "";
    } else {
      nextMetadata.ownerUserId = actor.id || "";
      nextMetadata.ownerUsername = actor.username || "";
      nextMetadata.ownerDisplayName = actor.displayName || actor.username || "";
    }
    if (author && editorUserId === undefined && !nextMetadata.editorUserId && author.managerUserId) {
      const manager = findActiveProjectUser(author.managerUserId, { role: "editor", tenantId: projectTenantId, store });
      nextMetadata.editorUserId = manager?.id || "";
      nextMetadata.editorUsername = manager?.username || "";
    }
  }

  if (editorUserId !== undefined) {
    const editor = findActiveProjectUser(editorUserId, { role: "editor", tenantId: projectTenantId, store });
    nextMetadata.editorUserId = editor?.id || "";
    nextMetadata.editorUsername = editor?.username || "";
  }

  writeProjectMetadata(paths.bookRoot, nextMetadata);
  return {
    ...listWorkspacesFromRoot(getWorkspaceParentRootFromPaths(paths)).find((item) =>
      item.bookName === bookName &&
      normalizeTenantId(item.project?.tenantId || DEFAULT_TENANT_ID) === projectTenantId
    ),
    project: getProjectPublicMetadata(getProjectMetadataForPaths(bookName, paths))
  };
}

function serveStatic(reqPath, res) {
  const target = reqPath === "/" ? "/index.html" : reqPath;
  const filePath = path.normalize(path.join(PUBLIC_DIR, target));

  if (!isPathInside(PUBLIC_DIR, filePath)) {
    sendText(res, 403, "Forbidden");
    return;
  }

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    sendText(res, 404, "Not found");
    return;
  }

  const ext = path.extname(filePath).toLowerCase();
  const types = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml; charset=utf-8"
  };

  sendText(res, 200, fs.readFileSync(filePath), types[ext] || "application/octet-stream");
}

function createJob(meta) {
  const id = randomUUID();
  const createdDate = new Date();
  const currentUser = getCurrentUserContext();
  const job = {
    id,
    status: "running",
    createdAt: createdDate.toISOString(),
    updatedAt: createdDate.toISOString(),
    timestamp: formatLocalTimestamp(createdDate),
    meta: {
      ...(meta || {}),
      userId: currentUser.id || "",
      username: currentUser.username || "",
      tenantId: getTenantIdFromUser(currentUser),
      tenantName: currentUser.tenantName || "",
      workspaceParentRoot: getWorkspaceParentRoot()
    },
    output: "",
    archived: false
  };
  Object.defineProperty(job, "child", {
    value: null,
    writable: true,
    enumerable: false,
    configurable: true
  });
  jobs.set(id, job);
  initializeJobPersistence(job, createdDate);
  recordAuditEvent("job.start", {
    actor: currentUser,
    targetUser: currentUser,
    status: "running",
    tenantId: getTenantIdFromUser(currentUser),
    route: job.meta.route || "",
    bookName: job.meta.bookName || "",
    jobId: job.id,
    message: `Started ${job.meta.route || "job"} for ${job.meta.bookName || ""}.`,
    data: {
      route: job.meta.route || "",
      bookName: job.meta.bookName || ""
    }
  });
  return job;
}

function appendJobOutput(job, chunk) {
  const text = String(chunk || "");
  if (!text) {
    return;
  }
  job.output += text;
  job.updatedAt = new Date().toISOString();
  appendJobOutputFile(job, text);
  persistJobState(job);
}

function appendJobLifecycleLine(job, message) {
  appendJobOutput(job, `[webui] ${message}\n`);
}

function finishJob(job, exitCode) {
  if (job.status === "cancelled") {
    job.child = null;
    job.childPid = null;
    return;
  }
  job.status = exitCode === 0 ? "success" : "failed";
  job.exitCode = exitCode;
  job.updatedAt = new Date().toISOString();
  job.child = null;
  job.childPid = null;
  const billing = recordJobTokenUsage(job);
  if (billing) {
    appendJobLifecycleLine(job, `Billing recorded. Tokens: ${billing.event.usage.total_tokens}. Credits: ${billing.event.chargedCredits}. Balance: ${billing.billing.balanceCredits}.`);
  }
  recordAuditEvent("job.finish", {
    actor: {
      id: job.meta?.userId || "",
      username: job.meta?.username || "",
      role: ""
    },
    targetUser: {
      id: job.meta?.userId || "",
      username: job.meta?.username || "",
      role: ""
    },
    status: job.status,
    tenantId: job.meta?.tenantId || "",
    route: job.meta?.route || "",
    bookName: job.meta?.bookName || "",
    jobId: job.id,
    message: `Finished ${job.meta?.route || "job"} with status ${job.status}.`,
    data: {
      exitCode: job.exitCode,
      chargedCredits: billing?.event?.chargedCredits || 0,
      totalTokens: billing?.event?.usage?.total_tokens || 0
    }
  });
  appendJobLifecycleLine(job, `Run finished. Job ID: ${job.id}. Status: ${job.status}. Exit code: ${job.exitCode}.`);
  archiveJobOutput(job);
  persistJobState(job);
}

function failJob(job, error) {
  if (job.status === "cancelled") {
    job.child = null;
    job.childPid = null;
    return;
  }
  job.status = "failed";
  job.exitCode = -1;
  job.updatedAt = new Date().toISOString();
  appendJobOutput(job, `\n[webui-error] ${error.message}\n`);
  job.child = null;
  job.childPid = null;
  const billing = recordJobTokenUsage(job);
  if (billing) {
    appendJobLifecycleLine(job, `Billing recorded. Tokens: ${billing.event.usage.total_tokens}. Credits: ${billing.event.chargedCredits}. Balance: ${billing.billing.balanceCredits}.`);
  }
  recordAuditEvent("job.finish", {
    actor: {
      id: job.meta?.userId || "",
      username: job.meta?.username || "",
      role: ""
    },
    targetUser: {
      id: job.meta?.userId || "",
      username: job.meta?.username || "",
      role: ""
    },
    status: "failed",
    tenantId: job.meta?.tenantId || "",
    route: job.meta?.route || "",
    bookName: job.meta?.bookName || "",
    jobId: job.id,
    message: error.message,
    data: {
      exitCode: job.exitCode,
      chargedCredits: billing?.event?.chargedCredits || 0,
      totalTokens: billing?.event?.usage?.total_tokens || 0
    }
  });
  appendJobLifecycleLine(job, `Run finished. Job ID: ${job.id}. Status: failed. Exit code: -1.`);
  archiveJobOutput(job);
  persistJobState(job);
}

function cancelJob(job) {
  if (!job) {
    throw new Error("Job not found.");
  }
  if (job.status !== "running") {
    return job;
  }
  if (!job.childPid) {
    throw new Error("No running process found for this job.");
  }

  const result = spawnSync("taskkill.exe", ["/PID", String(job.childPid), "/T", "/F"], {
    encoding: "utf8",
    windowsHide: true
  });

  if (result.stdout) {
    appendJobOutput(job, result.stdout);
  }
  if (result.stderr) {
    appendJobOutput(job, result.stderr);
  }
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || "Failed to stop current job.").trim());
  }

  job.status = "cancelled";
  job.exitCode = -999;
  job.updatedAt = new Date().toISOString();
  job.child = null;
  job.childPid = null;
  appendJobLifecycleLine(job, `Run cancelled. Job ID: ${job.id}.`);
  recordAuditEvent("job.cancel", {
    actor: getCurrentUserContext(),
    targetUser: {
      id: job.meta?.userId || "",
      username: job.meta?.username || "",
      role: ""
    },
    status: "cancelled",
    tenantId: job.meta?.tenantId || "",
    route: job.meta?.route || "",
    bookName: job.meta?.bookName || "",
    jobId: job.id,
    message: `Cancelled ${job.meta?.route || "job"}.`,
    data: {
      exitCode: job.exitCode
    }
  });
  archiveJobOutput(job);
  persistJobState(job);
  return job;
}

function archiveJobOutput(job) {
  if (job.archived) {
    return;
  }

  const bookName = job.meta?.bookName;
  if (!bookName) {
    job.archived = true;
    return;
  }

  try {
    const paths = getWorkspacePaths(bookName);
    ensureDir(paths.webRunRoot);
    const timestamp = formatLocalTimestamp();
    const route = sanitizeJobNamePart(job.meta.route);
    const fileName = job.meta.outputFileName || `${formatFileStamp()}-${route}-${job.id}.log`;
    validateWebRunOutputFileName(fileName);
    const outputPath = job.meta.outputPath && isPathInside(paths.webRunRoot, job.meta.outputPath)
      ? job.meta.outputPath
      : resolveInside(paths.webRunRoot, fileName);
    fs.writeFileSync(outputPath, job.output || "", "utf8");

    const entry = {
      source: "webui",
      timestamp,
      step: job.meta.route,
      state: job.status,
      message: deriveSummary(job.output || "", `Web UI ${job.meta.route} ${job.status}.`),
      data: {
        exitCode: job.exitCode,
        outputFileName: fileName,
        outputPath
      }
    };

    appendJsonLine(paths.webRunIndexPath, entry);
    job.meta.outputFileName = fileName;
    job.meta.outputPath = outputPath;
    job.meta.archivedAt = timestamp;
    job.archived = true;
  } catch (error) {
    job.output += `\n[webui-archive-error] ${error.message}\n`;
    job.archived = true;
  }
}

function validateBookName(bookName) {
  if (!bookName || typeof bookName !== "string") {
    throw new Error("BookName is required.");
  }
  if (!/^[A-Za-z0-9_-]+$/.test(bookName)) {
    throw new Error("BookName only supports letters, numbers, underscores, and hyphens.");
  }
}

function normalizeOutputFileName(fileName) {
  const normalized = normalizeSafeRelativePath(fileName);
  if (!/\.(docx|epub|pdf)$/i.test(normalized)) {
    throw new Error("Only .docx, .epub, or .pdf output files are supported.");
  }
  return normalized;
}

function resolveOutputDocumentPath(paths, fileName) {
  return resolveInside(paths.outputRoot, normalizeOutputFileName(fileName));
}

function validateAssetFileName(fileName) {
  assertFileNameOnly(fileName);
  if (!/\.(png|jpg|jpeg|webp|pdf)$/i.test(fileName)) {
    throw new Error("Unsupported asset file type.");
  }
}

function validateChapterFileName(fileName) {
  assertFileNameOnly(fileName);
  if (!/\.md$/i.test(fileName)) {
    throw new Error("Only Markdown chapter files are supported.");
  }
}

function validateWebRunOutputFileName(fileName) {
  assertFileNameOnly(fileName);
  if (!/\.log$/i.test(fileName)) {
    throw new Error("Only archived Web UI log files are supported.");
  }
}

function sanitizeImportedImageFileName(fileName, fallbackExt) {
  const ext = path.extname(String(fileName || "")).toLowerCase() || fallbackExt;
  if (![".png", ".jpg", ".jpeg", ".webp"].includes(ext)) {
    throw new Error("Unsupported image file type.");
  }

  const stem = path.basename(String(fileName || "external-base-image"), path.extname(String(fileName || "")))
    .replace(/[^\w.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72) || "external-base-image";
  return `${stem}${ext}`;
}

function sanitizeKdpFixImageFileName(fileName) {
  const ext = path.extname(String(fileName || "")).toLowerCase() || ".png";
  if (![".png", ".jpg", ".jpeg", ".webp"].includes(ext)) {
    throw new Error("Unsupported KDP fix image type.");
  }
  const stem = path.basename(String(fileName || "kdp-fix-image"), path.extname(String(fileName || "")))
    .replace(/[^\w.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80) || "kdp-fix-image";
  return `${stem}${ext}`;
}

function sanitizeKdpFixPdfFileName(fileName) {
  const ext = path.extname(String(fileName || "")).toLowerCase() || ".pdf";
  if (ext !== ".pdf") {
    throw new Error("Unsupported KDP fix PDF type.");
  }
  const stem = path.basename(String(fileName || "kdp-fix-pdf"), path.extname(String(fileName || "")))
    .replace(/[^\w.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 90) || "kdp-fix-pdf";
  return `${stem}.pdf`;
}

function resolveKdpAcceptanceFilePath(bookName, relativePath, allowedExtensions = [".pdf", ".png"]) {
  validateBookName(bookName);
  const paths = getWorkspacePaths(bookName);
  const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
  const cleanRelative = normalizeSafeRelativePath(relativePath, "KDP acceptance file path");
  const ext = path.extname(cleanRelative).toLowerCase();
  if (!allowedExtensions.includes(ext)) {
    throw new Error("Unsupported KDP acceptance file type.");
  }
  const targetPath = resolveInside(acceptanceRoot, cleanRelative);
  if (!fs.existsSync(targetPath) || !fs.statSync(targetPath).isFile()) {
    throw new Error("KDP acceptance file not found.");
  }
  return {
    paths,
    acceptanceRoot,
    targetPath,
    relativePath: cleanRelative,
    ext
  };
}

function getImageMimeTypeByPath(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return {
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".webp": "image/webp"
  }[ext] || "application/octet-stream";
}

function getPngDimensions(buffer) {
  if (!Buffer.isBuffer(buffer) || buffer.length < 24 || buffer.slice(0, 8).toString("hex") !== "89504e470d0a1a0a") {
    throw new Error("PNG data is invalid.");
  }
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20)
  };
}

function sanitizeImportedPdfFileName(fileName) {
  const ext = path.extname(String(fileName || "")).toLowerCase() || ".pdf";
  if (ext !== ".pdf") {
    throw new Error("Only PDF files can be submitted to the KDP acceptance tool.");
  }

  const stem = path.basename(String(fileName || "cover-upload"), path.extname(String(fileName || "")))
    .replace(/[^\w.-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 72) || "cover-upload";
  return `${stem}.pdf`;
}

function validateLanguageCode(languageCode) {
  if (!languageCode || typeof languageCode !== "string") {
    throw new Error("language is required.");
  }
  if (!/^[A-Za-z0-9_-]+$/.test(languageCode)) {
    throw new Error("Invalid language.");
  }
}

function validatePublishPlatform(platform) {
  if (!platform) {
    return;
  }
  if (!["amazon", "apple", "google", "kobo"].includes(platform)) {
    throw new Error("Invalid publish platform.");
  }
}

function validatePublishFileName(fileName) {
  assertFileNameOnly(fileName);
  if (!/\.(json|md|txt|png|jpg|jpeg|webp|pdf|epub|docx)$/i.test(fileName)) {
    throw new Error("Unsupported publish file type.");
  }
}

function resolveCoverSectionRoot(paths, section) {
  const nextRoot = path.join(paths.bookRoot, "07_cover", "next", "ebook");
  const nextPrintRoot = path.join(paths.bookRoot, "07_cover", "next", "print");
  switch (section) {
    case "drafts":
      return paths.coverDraftRoot;
    case "layout":
      return paths.coverLayoutRoot;
    case "mockup":
      return paths.coverMockupRoot;
    case "final":
      return paths.coverFinalRoot;
    case "kdp-acceptance":
      return getKdpAcceptanceRoot(paths.bookRoot);
    case "next-imports":
      return path.join(nextRoot, "imports");
    case "next-layout":
      return path.join(nextRoot, "layout");
    case "next-print-spread":
      return path.join(nextPrintRoot, "print_spread");
    case "next-mockup":
      return path.join(nextRoot, "mockup");
    case "next-final":
      return path.join(nextRoot, "final");
    default:
      throw new Error("Invalid cover section.");
  }
}

function resolvePublishSectionRoot(paths, languageCode, platform) {
  validateLanguageCode(languageCode);
  validatePublishPlatform(platform);

  const publishRoot = getPublishLanguageRoot(paths.bookRoot, languageCode);
  return platform ? path.join(publishRoot, platform) : publishRoot;
}

function openFileWithDefaultApp(filePath) {
  assertLocalOpenAllowed();
  const launcherPath = path.join(__dirname, "open-target.vbs");
  if (!fs.existsSync(launcherPath)) {
    throw new Error("Open target launcher not found.");
  }

  const child = spawn("wscript.exe", [
    launcherPath,
    filePath
  ], {
    detached: true,
    stdio: "ignore",
    windowsHide: false
  });

  child.unref();
}

function openFolder(folderPath) {
  assertLocalOpenAllowed();
  const launcherPath = path.join(__dirname, "open-target.vbs");
  if (!fs.existsSync(launcherPath)) {
    throw new Error("Open target launcher not found.");
  }

  const child = spawn("wscript.exe", [
    launcherPath,
    folderPath
  ], {
    detached: true,
    stdio: "ignore",
    windowsHide: false
  });

  child.unref();
}

function revealFileInExplorer(filePath) {
  assertLocalOpenAllowed();
  openFileWithDefaultApp(filePath);
}

function pushArg(args, flag, value) {
  if (value === undefined || value === null || value === "") {
    return;
  }
  args.push(flag, String(value));
}

function runScript(scriptName, params, meta) {
  const scriptPath = path.join(ENGINE_ROOT, scriptName);
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`Script not found: ${scriptName}`);
  }

  const job = createJob(meta);
  const args = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath
  ];

  params.forEach((item) => {
    if (item.type === "switch") {
      if (item.enabled) {
        args.push(item.flag);
      }
      return;
    }
    pushArg(args, item.flag, item.value);
  });

  appendJobLifecycleLine(job, `Run started. Job ID: ${job.id}. Route: ${meta?.route || ""}. Script: ${scriptName}.`);

  const child = spawn("powershell.exe", args, {
    cwd: ENGINE_ROOT,
    env: getChildProcessEnv(meta?.workspaceParentRoot)
  });

  job.child = child;
  job.childPid = child.pid;
  persistJobState(job);

  child.stdout.on("data", (chunk) => appendJobOutput(job, chunk.toString("utf8")));
  child.stderr.on("data", (chunk) => appendJobOutput(job, chunk.toString("utf8")));
  child.on("error", (error) => failJob(job, error));
  child.on("close", (code) => finishJob(job, code ?? -1));

  return job;
}

function getBookNameParam(params = []) {
  const item = params.find((param) => String(param?.flag || "").toLowerCase() === "-bookname");
  return item ? String(item.value || "").trim() : "";
}

function getWorkspaceParentRootForScriptParams(params = []) {
  const bookName = getBookNameParam(params);
  if (!bookName) {
    return getWorkspaceParentRoot();
  }
  validateBookName(bookName);
  const paths = getWorkspacePaths(bookName);
  return getWorkspaceParentRootFromPaths(paths);
}

function runPowerShellJson(scriptName, params = []) {
  const scriptPath = path.join(ENGINE_ROOT, scriptName);
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`Script not found: ${scriptName}`);
  }
  const args = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath
  ];
  params.forEach((item) => {
    if (item.type === "switch") {
      if (item.enabled) args.push(item.flag);
      return;
    }
    pushArg(args, item.flag, item.value);
  });
  const result = spawnSync("powershell.exe", args, {
    cwd: ENGINE_ROOT,
    env: getChildProcessEnv(getWorkspaceParentRootForScriptParams(params)),
    encoding: "utf8",
    maxBuffer: 20 * 1024 * 1024
  });
  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || `${scriptName} failed.`).trim());
  }
  const text = String(result.stdout || "").trim();
  if (!text) {
    return null;
  }
  return JSON.parse(text);
}

function runDetachedScript(scriptName, params, meta, message = "") {
  const scriptPath = path.join(ENGINE_ROOT, scriptName);
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`Script not found: ${scriptName}`);
  }

  const job = createJob(meta);
  const args = [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    scriptPath
  ];

  params.forEach((item) => {
    if (item.type === "switch") {
      if (item.enabled) {
        args.push(item.flag);
      }
      return;
    }
    pushArg(args, item.flag, item.value);
  });

  const child = spawn("powershell.exe", args, {
    cwd: ENGINE_ROOT,
    env: getChildProcessEnv(meta?.workspaceParentRoot),
    detached: true,
    stdio: "ignore"
  });

  child.unref();
  appendJobOutput(job, `${message || `${scriptName} started in detached mode.`}\n`);
  finishJob(job, 0);
  return job;
}

function toPowerShellSingleQuoted(value) {
  return `'${String(value ?? "").replace(/'/g, "''")}'`;
}

function launchScriptInNewConsole(scriptName, params, meta, message = "") {
  if (isCloudMode()) {
    return runScript(scriptName, params, meta);
  }

  const scriptPath = path.join(ENGINE_ROOT, scriptName);
  if (!fs.existsSync(scriptPath)) {
    throw new Error(`Script not found: ${scriptName}`);
  }

  const job = createJob(meta);
  const launcherPath = path.join(__dirname, "launch-powershell-file.vbs");
  if (!fs.existsSync(launcherPath)) {
    throw new Error("PowerShell launcher not found.");
  }

  const launchRoot = path.join(__dirname, "launchers");
  ensureDir(launchRoot);

  const wrapperPath = path.join(launchRoot, `${Date.now()}-${randomUUID()}.ps1`);
  const commandParts = [`& ${toPowerShellSingleQuoted(scriptPath)}`];
  params.forEach((item) => {
    if (item.type === "switch") {
      if (item.enabled) {
        commandParts.push(item.flag);
      }
      return;
    }
    commandParts.push(item.flag);
    commandParts.push(toPowerShellSingleQuoted(item.value));
  });

  const windowTitle = `SageWrite ${scriptName}`;
  const wrapperLines = [
    `$Host.UI.RawUI.WindowTitle = ${toPowerShellSingleQuoted(windowTitle)}`,
    "",
    commandParts.join(" "),
    ""
  ];
  fs.writeFileSync(wrapperPath, wrapperLines.join("\r\n"), "utf8");

  const child = spawn("wscript.exe", [
    launcherPath,
    wrapperPath,
    windowTitle
  ], {
    cwd: __dirname,
    env: getChildProcessEnv(meta?.workspaceParentRoot),
    detached: true,
    stdio: "ignore",
    windowsHide: false
  });

  child.unref();
  appendJobOutput(job, `${message || `${scriptName} started in a new console window.`}\n`);
  finishJob(job, 0);
  return job;
}

async function handleRun(route, body, res) {
  try {
    const bookName = body.bookName;
    validateBookName(bookName);
    const paths = getWorkspacePaths(bookName);
    const projectExists = fs.existsSync(paths.workspacePath);
    if (route === "intake") {
      ensureProjectMetadataForCurrentUser(bookName, paths);
    } else if (!projectExists) {
      throw new Error("Project workspace not found.");
    }
    const runMeta = {
      route,
      bookName,
      workspaceParentRoot: getWorkspaceParentRootFromPaths(paths),
      project: getProjectPublicMetadata(getProjectMetadataForPaths(bookName, paths))
    };

    let job;

    switch (route) {
      case "intake":
        [
          "title",
          "audience",
          "type",
          "coreThesis",
          "scope",
          "style"
        ].forEach((key) => {
          if (!body[key]) {
            throw new Error(`Missing field: ${key}`);
          }
        });
        job = runScript("01-intake.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Title", value: body.title },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Audience", value: body.audience },
          { flag: "-Type", value: body.type },
          { flag: "-CoreThesis", value: body.coreThesis },
          { flag: "-Scope", value: body.scope },
          { flag: "-Style", value: body.style }
        ], runMeta);
        break;
      case "structure":
        job = runScript("02-structure.ps1", [
          { flag: "-BookName", value: bookName }
        ], runMeta);
        break;
      case "expand":
        if (body.mode === "chapter") {
          if (!body.chapter) {
            throw new Error("Chapter is required.");
          }
        }
        if (body.mode === "range") {
          if (!body.startChapter || !body.endChapter) {
            throw new Error("StartChapter and EndChapter are required.");
          }
        }
        job = runScript("02b-expand.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Chapter", value: body.mode === "chapter" ? body.chapter : undefined },
          { flag: "-StartChapter", value: body.mode === "range" ? body.startChapter : undefined },
          { flag: "-EndChapter", value: body.mode === "range" ? body.endChapter : undefined },
          { flag: "-MinSubsections", value: body.minSubsections || 3 },
          { flag: "-MaxSubsections", value: body.maxSubsections || 5 },
          { flag: "-Model", value: body.model || "gpt-4o-mini" },
          { flag: "-All", type: "switch", enabled: body.mode === "all" }
        ], runMeta);
        break;
      case "write":
        if (!body.model) {
          throw new Error("Model is required.");
        }
        if (body.mode === "chapter" && !body.chapter) {
          throw new Error("Chapter is required.");
        }
        if (body.mode === "range" && (!body.startChapter || !body.endChapter)) {
          throw new Error("StartChapter and EndChapter are required.");
        }
        if (body.additionalInstructions && body.mode !== "chapter") {
          throw new Error("Additional instructions are only supported in single chapter mode.");
        }
        job = runScript("03-write.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Model", value: body.model || "gpt-5.2" },
          { flag: "-Chapter", value: body.mode === "chapter" ? body.chapter : undefined },
          { flag: "-StartChapter", value: body.mode === "range" ? body.startChapter : undefined },
          { flag: "-EndChapter", value: body.mode === "range" ? body.endChapter : undefined },
          { flag: "-MaxTokens", value: body.maxTokens || 6000 },
          { flag: "-AdditionalInstructions", value: body.additionalInstructions || undefined },
          { flag: "-ReferenceGlossary", type: "switch", enabled: Boolean(body.referenceGlossary) },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "translate":
        if (!body.language) {
          throw new Error("Language is required.");
        }
        body.model = String(body.model || "").trim() || "gpt-5.2";
        if (body.mode === "chapter" && (body.chapter === undefined || body.chapter === null || body.chapter === "")) {
          throw new Error("Chapter is required.");
        }
        if (body.mode === "range" && (!body.startChapter || !body.endChapter)) {
          throw new Error("StartChapter and EndChapter are required.");
        }
        job = runScript("03t-translate.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language },
          { flag: "-Model", value: body.model || "gpt-5.2" },
          { flag: "-Chapter", value: body.mode === "chapter" ? body.chapter : undefined },
          { flag: "-StartChapter", value: body.mode === "range" ? body.startChapter : undefined },
          { flag: "-EndChapter", value: body.mode === "range" ? body.endChapter : undefined },
          { flag: "-All", type: "switch", enabled: body.mode === "all" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "refine-translation":
        if (!body.language) {
          throw new Error("Language is required.");
        }
        if (!body.model) {
          throw new Error("Model is required.");
        }
        if (body.mode === "chapter" && !body.chapter) {
          throw new Error("Chapter is required.");
        }
        if (body.mode === "range" && (!body.startChapter || !body.endChapter)) {
          throw new Error("StartChapter and EndChapter are required.");
        }
        job = runScript("03r-refine.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language },
          { flag: "-Model", value: body.model || "gpt-5.2" },
          { flag: "-Chapter", value: body.mode === "chapter" ? body.chapter : undefined },
          { flag: "-StartChapter", value: body.mode === "range" ? body.startChapter : undefined },
          { flag: "-EndChapter", value: body.mode === "range" ? body.endChapter : undefined },
          { flag: "-All", type: "switch", enabled: body.mode === "all" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "edit":
        job = runScript("04-edit.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Strict", type: "switch", enabled: Boolean(body.strict) }
        ], runMeta);
        break;
      case "build":
        job = runScript("05-build.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], runMeta);
        break;
      case "build-simple":
        job = runScript("05a-simple-docx.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], runMeta);
        break;
      case "build-simple-toc":
        job = runScript("05aa-simple-docx-toc.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], runMeta);
        break;
      case "build-epub":
        job = runScript("05b-epub.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], runMeta);
        break;
      case "build-pdf":
        job = runScript("05c-pdf.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], runMeta);
        break;
      case "build-print-pdf":
        job = runScript("05cc-print-pdf.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-AutoNumber", type: "switch", enabled: Boolean(body.autoNumber) }
        ], runMeta);
        break;
      case "cover":
        job = runScript("08-cover.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) },
          { flag: "-SkipLayout", type: "switch", enabled: Boolean(body.skipLayout) },
          { flag: "-SkipMockup", type: "switch", enabled: Boolean(body.skipMockup) }
        ], runMeta);
        break;
      case "cover-drafts":
        job = runScript("08-cover-drafts.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-layout":
        job = runScript("08-cover-layout.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-mockup":
        job = runScript("08-cover-mockup.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-assist":
        job = runScript("07a-cover-assist.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Request", value: body.request || undefined },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Model", value: body.model || undefined }
        ], runMeta);
        break;
      case "cover-midjourney-prompt-ai":
        job = runScript("08n-midjourney-prompt.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Model", value: body.model || "gpt-5.2" }
        ], runMeta);
        break;
      case "cover-next":
        job = runScript("08n-cover.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) },
          { flag: "-SkipMockup", type: "switch", enabled: Boolean(body.skipMockup) },
          { flag: "-SkipPrintSpread", type: "switch", enabled: Boolean(body.skipPrintSpread) }
        ], runMeta);
        break;
      case "cover-next-brief":
        job = runScript("08n-base-brief.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-next-prompt":
        job = runScript("08n-base-prompt.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-next-generate":
        job = runScript("08n-base-generate.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-next-review":
        job = runScript("08n-base-review.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-next-layout":
        job = runScript("08n-title-layout.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-next-image-edit":
        job = runScript("08n-image-edit.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-InputFile", value: body.inputFile || undefined },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Publisher", value: body.publisher || undefined },
          { flag: "-CoverText", value: body.coverText || undefined },
          { flag: "-ImageModel", value: body.imageModel || "gpt-image-1.5" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "kdp-fix-image-edit":
        job = runScript("kdp-fix-image-edit.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-SourceFile", value: body.sourceFileName || undefined },
          { flag: "-PromptFile", value: body.promptFileName || undefined },
          { flag: "-Prompt", value: body.prompt || undefined },
          { flag: "-ImageModel", value: body.imageModel || "gpt-image-1.5" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "kdp-acceptance-files":
        job = runScript("kdp-acceptance-files.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Action", value: body.action || "List" }
        ], runMeta);
        break;
      case "kdp-imagemagick-fix":
        job = runScript("kdp-imagemagick-fix.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-SourceFile", value: body.sourceFileName || undefined },
          { flag: "-InputEditFile", value: body.inputEditFileName || undefined },
          { flag: "-InstructionJson", value: body.instructionJson || undefined },
          { flag: "-InstructionFile", value: body.instructionFileName || undefined },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-next-print":
        job = runScript("08n-cover.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: "print" },
          { flag: "-Title", value: body.title || undefined },
          { flag: "-Subtitle", value: body.subtitle || undefined },
          { flag: "-Author", value: body.author || undefined },
          { flag: "-Variants", value: body.variants || 4 },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-next-mockup":
        job = runScript("08n-mockup.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Mode", value: body.mode || "auto" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "cover-next-export":
        job = runScript("08n-export.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Edition", value: body.nextEdition || body.edition || "ebook" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "publish":
        job = runScript("09-publish.ps1", [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-Platform", value: body.platform || "all" },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
        ], runMeta);
        break;
      case "submit":
        if (!body.platform || body.platform === "all") {
          throw new Error("A specific platform is required for submit.");
        }
        {
          const submitParams = [
          { flag: "-BookName", value: bookName },
          { flag: "-Language", value: body.language || "zh" },
          { flag: "-Platform", value: body.platform },
          { flag: "-Mode", value: body.mode || "assist" },
          { flag: "-AttachChrome", type: "switch", enabled: ["google", "amazon"].includes(body.platform) && Boolean(body.attachChrome) },
          { flag: "-ChromeDebugPort", value: ["google", "amazon"].includes(body.platform) && Boolean(body.attachChrome) ? Number(body.chromeDebugPort || 9222) : undefined },
          { flag: "-ReuseSession", type: "switch", enabled: Boolean(body.reuseSession) },
          { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
          ];

          if (["assist", "details", "content"].includes(body.mode || "assist")) {
            const submitMode = body.mode || "assist";
            const launchMessage = submitMode === "content" && body.platform === "amazon" && Boolean(body.attachChrome)
              ? "Amazon second-page session started in a new PowerShell window. It should attach to the current debugging browser window instead of opening a new login flow."
              : submitMode === "details" && body.platform === "amazon"
                ? "Amazon details-page session started in a new PowerShell window."
                : "Submit assist session started in a new PowerShell window. Browser automation will continue from there.";
            job = launchScriptInNewConsole("09f-submit.ps1", submitParams, runMeta, launchMessage);
          } else {
            job = runScript("09f-submit.ps1", submitParams, runMeta);
          }
        }
        break;
      default:
        sendJson(res, 404, { error: "Unknown route." });
        return;
    }

    sendJson(res, 202, { jobId: job.id, status: job.status });
  } catch (error) {
    sendJson(res, 400, { error: error.message });
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === "GET" && url.pathname === "/api/auth/status") {
    const authenticatedUser = getAuthenticatedUserFromRequest(req);
    const currentUser = !isAuthEnabled()
      ? getUserPublic(getLegacyUserContext("local"))
      : authenticatedUser || null;
    sendJson(res, 200, {
      ...getPublicAuthDetails(),
      authenticated: !isAuthEnabled() || Boolean(authenticatedUser),
      currentUser
    });
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/auth/login") {
    try {
      if (!isAuthEnabled()) {
        sendJson(res, 200, { authenticated: true, authEnabled: false, currentUser: getUserPublic(getLegacyUserContext("local")) });
        return;
      }
      const body = await readJsonBody(req, 50_000);
      const password = typeof body.password === "string" ? body.password : "";

      if (isUserAuthEnabled()) {
        const username = typeof body.username === "string" ? body.username : "";
        const user = findUserByUsername(username);
        if (!user || !verifyPassword(password, user.password)) {
          recordAuditEvent("auth.login.failed", {
            req,
            actor: null,
            targetUser: user || null,
            status: "failed",
            message: "Invalid username or password.",
            data: {
              username: normalizeUsername(username)
            }
          });
          sendJson(res, 401, { error: "Invalid username or password.", authRequired: true });
          return;
        }
        if (user.disabled) {
          recordAuditEvent("auth.login.disabled", {
            req,
            actor: null,
            targetUser: user,
            status: "failed",
            message: "Disabled user attempted to login."
          });
          sendJson(res, 403, { error: "User account is disabled.", authRequired: true });
          return;
        }
        const userWorkspaceRoot = getUserWorkspaceRoot(user);
        ensureDir(userWorkspaceRoot);
        const token = createSession(user);
        recordAuditEvent("auth.login.success", {
          req,
          actor: user,
          targetUser: user,
          status: "success",
          message: "User logged in."
        });
        res.writeHead(200, {
          "Content-Type": "application/json; charset=utf-8",
          "Cache-Control": "no-store",
          "Set-Cookie": `${SESSION_COOKIE}=${encodeURIComponent(token)}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${Math.floor(SESSION_TTL_MS / 1000)}`
        });
        res.end(JSON.stringify({
          authenticated: true,
          authEnabled: true,
          authMode: AUTH_MODE,
          currentUser: sessions.get(token)?.user || null
        }));
        return;
      }

      if (!ADMIN_PASSWORD) {
        sendJson(res, 500, { error: "SAGEWRITE_ADMIN_PASSWORD is not set." });
        return;
      }
      if (!safeEqualText(password, ADMIN_PASSWORD)) {
        sendJson(res, 401, { error: "Invalid password.", authRequired: true });
        return;
      }
      const token = createSession(getLegacyUserContext("password"));
      res.writeHead(200, {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "no-store",
        "Set-Cookie": `${SESSION_COOKIE}=${encodeURIComponent(token)}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${Math.floor(SESSION_TTL_MS / 1000)}`
      });
      res.end(JSON.stringify({ authenticated: true, authEnabled: true, authMode: AUTH_MODE, currentUser: sessions.get(token)?.user || null }));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/auth/logout") {
    const token = parseCookies(req)[SESSION_COOKIE];
    const user = getAuthenticatedUserFromRequest(req);
    if (user) {
      recordAuditEvent("auth.logout", {
        req,
        actor: user,
        targetUser: user,
        status: "success",
        message: "User logged out."
      });
    }
    if (token) {
      sessions.delete(token);
    }
    res.writeHead(200, {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Set-Cookie": `${SESSION_COOKIE}=; HttpOnly; SameSite=Lax; Path=/; Max-Age=0`
    });
    res.end(JSON.stringify({ authenticated: false }));
    return;
  }

  if (!requireAuth(req, res, url)) {
    return;
  }
  requestContext.enterWith({ user: req.sagewriteUser || getCurrentUserContext() });
  if (!authorizeProjectApiRequest(req, res, url)) {
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/status") {
    const currentUser = getCurrentUserContext();
    const showServerPaths = canCurrentUserSeeServerPaths();
    sendJson(res, 200, {
      engineRoot: showServerPaths ? ENGINE_ROOT : "",
      clawRoot: showServerPaths ? CLAW_ROOT : "",
      workspaceParentRoot: getWorkspaceParentRoot(),
      globalWorkspaceParentRoot: showServerPaths ? WORKSPACE_PARENT_ROOT : "",
      appMode: APP_MODE,
      authMode: AUTH_MODE,
      billing: getBillingConfigPublic(),
      currentUser: getUserPublic(currentUser),
      hasOpenAIKey: Boolean(process.env.OPENAI_API_KEY),
      workspaces: listWorkspaces()
    });
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/account") {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const currentUser = getCurrentUserContext();
      const user = findUserById(currentUser.id);
      if (!user || user.disabled) {
        sendJson(res, 404, { error: "User not found." });
        return;
      }
      const limit = Number(url.searchParams.get("limit") || 20);
      sendJson(res, 200, {
        user: getUserPublic(user),
        billing: getUserBillingPublic(user),
        billingConfig: getBillingConfigPublic(),
        events: getUserBillingEvents(user.id, limit)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/account/password") {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const body = await readJsonBody(req, 100_000);
      if (body.newPassword !== body.confirmPassword) {
        throw new Error("New password confirmation does not match.");
      }
      const currentToken = parseCookies(req)[SESSION_COOKIE];
      const user = changeOwnPassword(getCurrentUserContext().id, body.currentPassword, body.newPassword);
      deleteSessionsForUser(user.id, currentToken);
      recordAuditEvent("account.password.change", {
        req,
        actor: user,
        targetUser: user,
        status: "success",
        message: "User changed own password."
      });
      sendJson(res, 200, { user });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/users") {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const managerUser = assertCurrentUserCanUseUserManagement();
      const store = ensureUserStore();
      sendJson(res, 200, {
        users: getVisibleUsersForActor(managerUser, store).map((user) => getUserPublic(user)),
        tenants: getVisibleTenantsForUser(managerUser, store),
        assignableEditors: getAssignableEditorsForActor(managerUser, store).map((user) => getUserPublic(user)),
        canManageTenants: isPlatformAdmin(managerUser),
        canManageUsers: canManageTenantUsers(managerUser),
        canManageAuthors: canManageAssignedAuthors(managerUser),
        canAdjustBilling: canManageTenantUsers(managerUser),
        currentTenantId: getTenantIdFromUser(managerUser)
      });
    } catch (error) {
      sendJson(res, 403, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/admin/audit") {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const adminUser = assertCurrentUserIsAdmin();
      const events = getAuditEvents({
        limit: url.searchParams.get("limit") || 100,
        action: url.searchParams.get("action") || "",
        user: url.searchParams.get("user") || "",
        status: url.searchParams.get("status") || "",
        actor: adminUser
      });
      sendJson(res, 200, {
        events,
        total: events.length,
        path: canCurrentUserSeeServerPaths() ? USER_AUDIT_LOG_PATH : ""
      });
    } catch (error) {
      sendJson(res, error.message === "Admin permission is required." ? 403 : 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/users") {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const managerUser = assertCurrentUserCanUseUserManagement();
      const body = await readJsonBody(req, 100_000);
      const user = createUserAccount({
        username: body.username,
        password: body.password,
        displayName: body.displayName,
        role: body.role,
        initialCredits: body.initialCredits,
        tenantId: body.tenantId,
        tenantName: body.tenantName,
        managerUserId: body.managerUserId,
        actor: managerUser
      });
      recordAuditEvent("user.create", {
        req,
        actor: managerUser,
        targetUser: user,
        status: "success",
        message: `Created user ${user.username}.`,
        data: {
          role: user.role,
          tenantId: user.tenantId || "",
          managerUserId: user.managerUserId || "",
          initialCredits: user.billing?.initialCredits || 0
        }
      });
      sendJson(res, 201, { user });
    } catch (error) {
      sendJson(res, getPermissionErrorStatus(error), { error: error.message });
    }
    return;
  }

  const userBillingMatch = url.pathname.match(/^\/api\/users\/([^/]+)\/billing$/);
  if (req.method === "GET" && userBillingMatch) {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const managerUser = assertCurrentUserCanUseUserManagement();
      const userId = decodeURIComponent(userBillingMatch[1]);
      const store = ensureUserStore();
      const user = getManageableUserById(managerUser, userId, store);
      if (!user) {
        sendJson(res, 404, { error: "User not found." });
        return;
      }
      const limit = Number(url.searchParams.get("limit") || 30);
      sendJson(res, 200, {
        user: getUserPublic(user),
        billing: getUserBillingPublic(user),
        events: getUserBillingEvents(user.id, limit)
      });
    } catch (error) {
      sendJson(res, getPermissionErrorStatus(error), { error: error.message });
    }
    return;
  }

  const userBillingAdjustmentMatch = url.pathname.match(/^\/api\/users\/([^/]+)\/billing-adjustment$/);
  if (req.method === "POST" && userBillingAdjustmentMatch) {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const adminUser = assertCurrentUserIsAdmin();
      const body = await readJsonBody(req, 100_000);
      const store = ensureUserStore();
      const targetUser = getManageableUserById(adminUser, decodeURIComponent(userBillingAdjustmentMatch[1]), store);
      if (!targetUser) {
        sendJson(res, 404, { error: "User not found." });
        return;
      }
      const result = recordUserBillingAdjustment(decodeURIComponent(userBillingAdjustmentMatch[1]), {
        creditDelta: body.creditDelta,
        note: body.note,
        adminUser
      });
      recordAuditEvent("billing.adjust", {
        req,
        actor: adminUser,
        targetUser: result.user,
        status: "success",
        message: `Adjusted credits for ${result.user.username}.`,
        data: {
          creditDelta: result.event.creditDelta,
          balanceCredits: result.billing.balanceCredits,
          note: result.event.note || ""
        }
      });
      sendJson(res, 200, {
        user: result.user,
        billing: result.billing,
        event: getUserBillingEvents(result.user.id, 1)[0] || result.event,
        events: getUserBillingEvents(result.user.id, 30)
      });
    } catch (error) {
      sendJson(res, error.message === "Admin permission is required." ? 403 : 400, { error: error.message });
    }
    return;
  }

  const userPasswordMatch = url.pathname.match(/^\/api\/users\/([^/]+)\/password$/);
  if (req.method === "POST" && userPasswordMatch) {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const managerUser = assertCurrentUserCanUseUserManagement();
      const body = await readJsonBody(req, 100_000);
      const user = resetUserPassword(decodeURIComponent(userPasswordMatch[1]), body.password, managerUser);
      deleteSessionsForUser(user.id, parseCookies(req)[SESSION_COOKIE]);
      recordAuditEvent("user.password.reset", {
        req,
        actor: managerUser,
        targetUser: user,
        status: "success",
        message: `Reset password for ${user.username}.`
      });
      sendJson(res, 200, { user });
    } catch (error) {
      sendJson(res, getPermissionErrorStatus(error), { error: error.message });
    }
    return;
  }

  const userAccountMatch = url.pathname.match(/^\/api\/users\/([^/]+)$/);
  if (req.method === "PATCH" && userAccountMatch) {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const managerUser = assertCurrentUserCanUseUserManagement();
      const body = await readJsonBody(req, 100_000);
      const updates = {};
      if (Object.hasOwn(body, "role")) {
        updates.role = body.role;
      }
      if (Object.hasOwn(body, "disabled")) {
        updates.disabled = body.disabled;
      } else if (Object.hasOwn(body, "status")) {
        updates.disabled = String(body.status || "").toLowerCase() === "disabled";
      }
      if (Object.hasOwn(body, "tenantId")) {
        updates.tenantId = body.tenantId;
        updates.tenantName = body.tenantName;
      }
      if (Object.hasOwn(body, "managerUserId")) {
        updates.managerUserId = body.managerUserId;
      }
      if (!Object.keys(updates).length) {
        throw new Error("No user updates were provided.");
      }
      const user = updateUserAccount(decodeURIComponent(userAccountMatch[1]), updates, managerUser);
      if (user.disabled) {
        deleteSessionsForUser(user.id);
      }
      recordAuditEvent("user.update", {
        req,
        actor: managerUser,
        targetUser: user,
        status: "success",
        message: `Updated user ${user.username}.`,
        data: updates
      });
      sendJson(res, 200, { user });
    } catch (error) {
      sendJson(res, getPermissionErrorStatus(error), { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/projects") {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const actor = getCurrentUserContext();
      const store = ensureUserStore();
      sendJson(res, 200, {
        projects: listProjectsForActor(actor),
        assignableAuthors: getAssignableAuthorsForActor(actor, store).map(getProjectUserOptionPublic).filter(Boolean),
        assignableEditors: getAssignableEditorsForActor(actor, store).map(getProjectUserOptionPublic).filter(Boolean),
        canManageProjects: canManageCompanyProjects(actor),
        canManageTenants: isPlatformAdmin(actor),
        currentTenantId: getTenantIdFromUser(actor)
      });
    } catch (error) {
      sendJson(res, getPermissionErrorStatus(error), { error: error.message });
    }
    return;
  }

  if (req.method === "PATCH" && url.pathname === "/api/projects") {
    try {
      if (!isUserAuthEnabled()) {
        sendJson(res, 400, { error: "User account mode is not enabled." });
        return;
      }
      const actor = assertCurrentUserCanManageProjects();
      const body = await readJsonBody(req, 100_000);
      const updates = {
        bookName: body.bookName,
        tenantId: body.tenantId || "",
        authorUserId: Object.hasOwn(body, "authorUserId") ? body.authorUserId : undefined,
        editorUserId: Object.hasOwn(body, "editorUserId") ? body.editorUserId : undefined
      };
      const project = updateProjectMetadataForActor(updates, actor);
      recordAuditEvent("project.update", {
        req,
        actor,
        status: "success",
        tenantId: project?.project?.tenantId || updates.tenantId || "",
        bookName: updates.bookName || "",
        message: `Updated project ${updates.bookName || ""}.`,
        data: {
          tenantId: updates.tenantId || "",
          authorUserId: updates.authorUserId === undefined ? "" : String(updates.authorUserId || ""),
          editorUserId: updates.editorUserId === undefined ? "" : String(updates.editorUserId || "")
        }
      });
      sendJson(res, 200, {
        project,
        projects: listProjectsForActor(actor)
      });
    } catch (error) {
      sendJson(res, getPermissionErrorStatus(error), { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/health") {
    try {
      sendJson(res, 200, buildSystemHealthReport());
    } catch (error) {
      sendJson(res, 500, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/objective-md") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const objectiveMarkdown = typeof body.objectiveMarkdown === "string" ? body.objectiveMarkdown : null;

      validateBookName(bookName);
      if (objectiveMarkdown === null) {
        throw new Error("objectiveMarkdown is required.");
      }

      const paths = getWorkspacePaths(bookName);
      ensureProjectMetadataForCurrentUser(bookName, paths);
      const briefRoot = path.join(paths.bookRoot, "00_brief");
      const objectivePath = path.join(briefRoot, "objective.md");

      ensureDir(briefRoot);
      fs.writeFileSync(objectivePath, objectiveMarkdown, "utf8");

      sendJson(res, 200, {
        saved: true,
        bookName,
        objectiveContent: objectiveMarkdown,
        objectiveData: parseFrontMatterMarkdown(objectivePath) || {},
        objectiveRelativePath: "00_brief/objective.md",
        objectivePath
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/output-file") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const outputPath = resolveOutputDocumentPath(paths, fileName);

      if (!fs.existsSync(outputPath)) {
        sendJson(res, 404, { error: "Output document not found." });
        return;
      }

      sendDiskFile(res, outputPath, path.extname(outputPath).toLowerCase() === ".pdf" ? "inline" : "attachment");
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-output") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const fileName = body.fileName;

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const outputPath = resolveOutputDocumentPath(paths, fileName);

      if (!fs.existsSync(outputPath)) {
        sendJson(res, 404, { error: "Output document not found." });
        return;
      }

      if (isCloudMode()) {
        sendJson(res, 200, cloudFilePayload({
          bookName,
          fileName
        }, outputPath, withQuery("/api/output-file", { bookName, fileName })));
        return;
      }

      openFileWithDefaultApp(outputPath);
      sendJson(res, 200, {
        opened: true,
        cloudMode: false,
        mode: APP_MODE,
        bookName,
        fileName,
        path: outputPath
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-output-folder") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const fileName = body.fileName;

      validateBookName(bookName);

      const paths = getWorkspacePaths(bookName);
      const targetFolder = fileName
        ? path.dirname(resolveOutputDocumentPath(paths, fileName))
        : paths.outputRoot;

      if (!fs.existsSync(targetFolder)) {
        sendJson(res, 404, { error: "Output folder not found." });
        return;
      }

      if (isCloudMode()) {
        sendJson(res, 200, cloudFolderPayload({
          bookName,
          fileName: fileName || ""
        }, targetFolder));
        return;
      }

      openFolder(targetFolder);
      sendJson(res, 200, {
        opened: true,
        cloudMode: false,
        mode: APP_MODE,
        bookName,
        fileName: fileName || "",
        path: targetFolder
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/reveal-output") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const fileName = body.fileName;

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const outputPath = resolveOutputDocumentPath(paths, fileName);

      if (!fs.existsSync(outputPath)) {
        sendJson(res, 404, { error: "Output document not found." });
        return;
      }

      if (isCloudMode()) {
        sendJson(res, 200, cloudFilePayload({
          bookName,
          fileName
        }, outputPath, withQuery("/api/output-file", { bookName, fileName })));
        return;
      }

      revealFileInExplorer(outputPath);
      sendJson(res, 200, {
        opened: true,
        cloudMode: false,
        mode: APP_MODE,
        bookName,
        fileName,
        path: outputPath
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/publish") {
    const bookName = url.searchParams.get("bookName");
    const language = url.searchParams.get("language") || "zh";

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      validateLanguageCode(language);
      const paths = getWorkspacePaths(bookName);
      sendJson(res, 200, {
        bookName,
        language,
        publish: getPublishArtifacts(paths.bookRoot, language)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/publish-metadata") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";

      validateBookName(bookName);
      validateLanguageCode(language);

      const paths = getWorkspacePaths(bookName);
      const publishRoot = getPublishLanguageRoot(paths.bookRoot, language);
      const metadataPath = path.join(publishRoot, "publish_metadata.json");

      if (!fs.existsSync(metadataPath)) {
        sendJson(res, 404, { error: "publish_metadata.json not found." });
        return;
      }

      const existing = readJsonFile(metadataPath);
      let nextMetadata;

      if (typeof body.metadataMarkdown === "string") {
        const parsed = parsePublishMetadataMarkdown(body.metadataMarkdown, existing);
        nextMetadata = {
          ...existing,
          title: parsed.title,
          subtitle: parsed.subtitle,
          author: parsed.author,
          language: parsed.language || existing.language || language,
          language_name: parsed.language_name || existing.language_name,
          publisher: parsed.publisher,
          imprint: parsed.imprint,
          edition_type: parsed.edition_type || existing.edition_type,
          publication_date: parsed.publication_date,
          rights: parsed.rights,
          copyright_holder: parsed.copyright_holder || existing.copyright_holder,
          territory: parsed.territory,
          distribution_rights: parsed.distribution_rights,
          short_description: parsed.short_description,
          long_description: parsed.long_description,
          marketing_tagline: parsed.marketing_tagline,
          cover_hook: parsed.cover_hook,
          back_cover_blurb: parsed.back_cover_blurb,
          obi_copy: parsed.obi_copy,
          author_bio: parsed.author_bio,
          spine_text: parsed.spine_text,
          keywords: parsed.keywords,
          categories: parsed.categories,
          formats: parsed.formats,
          platform_recommended_categories: parsed.platform_recommended_categories,
          platform_selected_categories: parsed.platform_selected_categories
        };
      } else {
        const keywords = sanitizeList(body.keywords);
        const categories = sanitizeList(body.categories);
        const selectedPlatformCategories = body.selectedPlatformCategories && typeof body.selectedPlatformCategories === "object"
          ? body.selectedPlatformCategories
          : (existing.platform_selected_categories || {});

        const title = sanitizeText(body.title || existing.title);
        const subtitle = sanitizeText(body.subtitle || existing.subtitle);
        const author = sanitizeText(body.author || existing.author);
        const publisher = sanitizeText(body.publisher || existing.publisher);
        const imprint = sanitizeText(body.imprint || existing.imprint);
        const publicationDate = sanitizeText(body.publicationDate || existing.publication_date);
        const rights = sanitizeText(body.rights || existing.rights);
        const territory = sanitizeText(body.territory || existing.territory);
        const distributionRights = sanitizeText(body.distributionRights || existing.distribution_rights);
        const shortDescription = sanitizeText(body.shortDescription || existing.short_description);
        const longDescription = sanitizeText(body.longDescription || existing.long_description);
        const marketingTagline = sanitizeText(body.marketingTagline || existing.marketing_tagline);
        const coverHook = sanitizeText(body.coverHook || existing.cover_hook);
        const backCoverBlurb = sanitizeText(body.backCoverBlurb || existing.back_cover_blurb);
        const obiCopy = sanitizeText(body.obiCopy || existing.obi_copy);
        const authorBio = sanitizeText(body.authorBio || existing.author_bio);
        const spineText = sanitizeText(body.spineText || existing.spine_text);

        nextMetadata = {
          ...existing,
          title,
          subtitle,
          author,
          publisher,
          imprint,
          publication_date: publicationDate,
          rights,
          territory,
          distribution_rights: distributionRights,
          short_description: shortDescription,
          long_description: longDescription,
          marketing_tagline: marketingTagline,
          cover_hook: coverHook,
          back_cover_blurb: backCoverBlurb,
          obi_copy: obiCopy,
          author_bio: authorBio,
          spine_text: spineText,
          keywords,
          categories,
          platform_selected_categories: {
            amazon: sanitizeText(selectedPlatformCategories.amazon),
            apple: sanitizeText(selectedPlatformCategories.apple),
            google: sanitizeText(selectedPlatformCategories.google)
          }
        };
      }

      nextMetadata.identification = {
        ...(existing.identification || {}),
        title: nextMetadata.title,
        subtitle: nextMetadata.subtitle,
        author: nextMetadata.author,
        publication_date: nextMetadata.publication_date,
        publisher: nextMetadata.publisher,
        imprint: nextMetadata.imprint
      };

      nextMetadata.marketing = {
        ...(existing.marketing || {}),
        tagline: nextMetadata.marketing_tagline,
        subtitle: nextMetadata.subtitle,
        short_description: nextMetadata.short_description,
        long_description: nextMetadata.long_description,
        cover_hook: nextMetadata.cover_hook,
        back_cover_blurb: nextMetadata.back_cover_blurb,
        obi_copy: nextMetadata.obi_copy,
        author_bio: nextMetadata.author_bio,
        spine_text: nextMetadata.spine_text
      };

      nextMetadata.rights_metadata = {
        ...(existing.rights_metadata || {}),
        rights_statement: nextMetadata.rights,
        territory: nextMetadata.territory,
        distribution_rights: nextMetadata.distribution_rights,
        publisher: nextMetadata.publisher,
        imprint: nextMetadata.imprint
      };

      nextMetadata.discovery = {
        ...(existing.discovery || {}),
        keywords: nextMetadata.keywords || [],
        categories: nextMetadata.categories || [],
        platform_recommended_categories: nextMetadata.platform_recommended_categories || existing.platform_recommended_categories || existing.discovery?.platform_recommended_categories || {},
        platform_selected_categories: {
          amazon: sanitizeText(nextMetadata.platform_selected_categories?.amazon),
          apple: sanitizeText(nextMetadata.platform_selected_categories?.apple),
          google: sanitizeText(nextMetadata.platform_selected_categories?.google)
        }
      };

      if (typeof body.metadataMarkdown === "string") {
        if (!Array.isArray(nextMetadata.keywords) || !nextMetadata.keywords.length) {
          nextMetadata.keywords = sanitizeList(extractMarkdownBulletSection(body.metadataMarkdown, "Keywords"));
          nextMetadata.discovery.keywords = nextMetadata.keywords;
        }
        if (!Array.isArray(nextMetadata.categories) || !nextMetadata.categories.length) {
          nextMetadata.categories = sanitizeList(extractMarkdownBulletSection(body.metadataMarkdown, "Categories"));
          nextMetadata.discovery.categories = nextMetadata.categories;
        }
        if (!Array.isArray(nextMetadata.formats) || !nextMetadata.formats.length) {
          nextMetadata.formats = sanitizeList(extractMarkdownBulletSection(body.metadataMarkdown, "Formats"));
        }
      }

      syncPublishMetadataFiles(paths.bookRoot, language, nextMetadata);

      sendJson(res, 200, {
        saved: true,
        bookName,
        language,
        publish: getPublishArtifacts(paths.bookRoot, language)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/amazon-description") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";
      const descriptionText = sanitizeText(body.descriptionText);

      validateBookName(bookName);
      validateLanguageCode(language);

      if (!descriptionText) {
        sendJson(res, 400, { error: "Description text is required." });
        return;
      }

      const paths = getWorkspacePaths(bookName);
      const publishRoot = getPublishLanguageRoot(paths.bookRoot, language);
      const amazonRoot = path.join(publishRoot, "amazon");
      const textPath = path.join(amazonRoot, "amazon_description.txt");
      const htmlPath = path.join(amazonRoot, "amazon_description.html");
      const sourceMarkdownPath = getLocalizedAmazonDescriptionSourcePath(paths.bookRoot, language);
      const metadata = readJsonFileSafe(path.join(publishRoot, "publish_metadata.json")) || {};

      ensureDir(amazonRoot);
      ensureDir(path.dirname(sourceMarkdownPath));
      fs.writeFileSync(textPath, `${descriptionText}\n`, "utf8");
      fs.writeFileSync(htmlPath, `${convertPlainTextToAmazonHtml(descriptionText)}\n`, "utf8");
      fs.writeFileSync(
        sourceMarkdownPath,
        buildAmazonDescriptionSourceMarkdown({
          metadata,
          language,
          descriptionText
        }),
        "utf8"
      );

      sendJson(res, 200, {
        saved: true,
        bookName,
        language,
        textFileName: path.basename(textPath),
        textPath: path.relative(paths.bookRoot, textPath),
        textFullPath: textPath,
        htmlFileName: path.basename(htmlPath),
        htmlPath: path.relative(paths.bookRoot, htmlPath),
        htmlFullPath: htmlPath,
        sourceMarkdownFileName: path.basename(sourceMarkdownPath),
        sourceMarkdownPath: path.relative(paths.bookRoot, sourceMarkdownPath),
        sourceMarkdownFullPath: sourceMarkdownPath,
        publish: getPublishArtifacts(paths.bookRoot, language)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-publish-folder") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";
      const platform = body.platform || "";

      validateBookName(bookName);
      validateLanguageCode(language);
      validatePublishPlatform(platform);

      const paths = getWorkspacePaths(bookName);
      const targetFolder = resolvePublishSectionRoot(paths, language, platform || "");

      if (!fs.existsSync(targetFolder)) {
        sendJson(res, 404, { error: "Publish folder not found." });
        return;
      }

      if (isCloudMode()) {
        sendJson(res, 200, cloudFolderPayload({
          bookName,
          language,
          platform
        }, targetFolder));
        return;
      }

      openFolder(targetFolder);
      sendJson(res, 200, {
        opened: true,
        cloudMode: false,
        mode: APP_MODE,
        bookName,
        language,
        platform,
        path: targetFolder
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/publish-file") {
    const bookName = url.searchParams.get("bookName");
    const language = url.searchParams.get("language") || "zh";
    const platform = url.searchParams.get("platform") || "";
    const fileName = url.searchParams.get("fileName");

    try {
      validateBookName(bookName);
      validateLanguageCode(language);
      validatePublishPlatform(platform);
      validatePublishFileName(fileName);

      const paths = getWorkspacePaths(bookName);
      const targetRoot = resolvePublishSectionRoot(paths, language, platform || "");
      const targetPath = resolveInside(targetRoot, fileName);

      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Publish file not found." });
        return;
      }

      sendDiskFile(res, targetPath, path.extname(targetPath).toLowerCase() === ".pdf" ? "inline" : "attachment");
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/reveal-publish-file") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";
      const platform = body.platform || "";
      const fileName = body.fileName;

      validateBookName(bookName);
      validateLanguageCode(language);
      validatePublishPlatform(platform);
      validatePublishFileName(fileName);

      const paths = getWorkspacePaths(bookName);
      const targetRoot = resolvePublishSectionRoot(paths, language, platform || "");
      const targetPath = resolveInside(targetRoot, fileName);

      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Publish file not found." });
        return;
      }

      if (isCloudMode()) {
        sendJson(res, 200, cloudFilePayload({
          bookName,
          language,
          platform,
          fileName
        }, targetPath, withQuery("/api/publish-file", { bookName, language, platform, fileName })));
        return;
      }

      revealFileInExplorer(targetPath);
      sendJson(res, 200, {
        opened: true,
        cloudMode: false,
        mode: APP_MODE,
        bookName,
        language,
        platform,
        fileName,
        path: targetPath
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-publish-file") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";
      const platform = body.platform || "";
      const fileName = body.fileName;

      validateBookName(bookName);
      validateLanguageCode(language);
      validatePublishPlatform(platform);
      validatePublishFileName(fileName);

      const paths = getWorkspacePaths(bookName);
      const targetRoot = resolvePublishSectionRoot(paths, language, platform || "");
      const targetPath = resolveInside(targetRoot, fileName);

      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Publish file not found." });
        return;
      }

      if (isCloudMode()) {
        sendJson(res, 200, cloudFilePayload({
          bookName,
          language,
          platform,
          fileName
        }, targetPath, withQuery("/api/publish-file", { bookName, language, platform, fileName })));
        return;
      }

      openFileWithDefaultApp(targetPath);
      sendJson(res, 200, {
        opened: true,
        cloudMode: false,
        mode: APP_MODE,
        bookName,
        language,
        platform,
        fileName,
        path: targetPath
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/generate-kobo-account-md") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const language = body.language || "zh";

      validateBookName(bookName);
      validateLanguageCode(language);

      const paths = getWorkspacePaths(bookName);
      const publishRoot = getPublishLanguageRoot(paths.bookRoot, language);
      const koboRoot = path.join(publishRoot, "kobo");
      const metadataPath = path.join(publishRoot, "publish_metadata.json");
      const objectivePath = path.join(paths.bookRoot, "00_brief", "objective.md");
      const outputPath = path.join(koboRoot, "kobo_account_basic_info.md");

      ensureDir(publishRoot);
      ensureDir(koboRoot);

      const metadata = readJsonFileSafe(metadataPath) || {};
      const objectiveData = parseFrontMatterMarkdown(objectivePath) || {};
      const markdown = buildKoboAccountBasicInfoMarkdown({
        bookName,
        language,
        metadata,
        objectiveData
      });

      fs.writeFileSync(outputPath, markdown, "utf8");

      const downloadUrl = withQuery("/api/publish-file", {
        bookName,
        language,
        platform: "kobo",
        fileName: "kobo_account_basic_info.md"
      });
      if (!isCloudMode()) {
        openFileWithDefaultApp(outputPath);
      }

      sendJson(res, 200, {
        generated: true,
        opened: !isCloudMode(),
        cloudMode: isCloudMode(),
        mode: APP_MODE,
        bookName,
        language,
        fileName: "kobo_account_basic_info.md",
        relativePath: path.relative(paths.bookRoot, outputPath),
        path: outputPath,
        downloadUrl,
        message: isCloudMode()
          ? "云端模式不会打开服务器桌面；请使用浏览器下载/预览链接。"
          : "Kobo basic info file opened."
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && /^\/api\/jobs\/[^/]+\/cancel$/.test(url.pathname)) {
    const jobId = url.pathname.split("/")[3];
    const job = jobs.get(jobId);
    if (!job || !doesJobBelongToCurrentUser(job)) {
      sendJson(res, 404, { error: "Job not found." });
      return;
    }
    if (!canRunRoute(getCurrentUserContext(), job.meta?.route || "")) {
      denyRoleAccess(req, res, "cancel_job", {
        pathname: url.pathname,
        method: req.method,
        route: job.meta?.route || "",
        bookName: job.meta?.bookName || "",
        jobId: job.id,
        message: "当前角色不能停止这个任务。"
      });
      return;
    }

    try {
      cancelJob(job);
      sendJson(res, 200, { ok: true, job });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/jobs/active") {
    const bookName = url.searchParams.get("bookName") || "";
    try {
      if (bookName) {
        validateBookName(bookName);
      }
      const job = findRunningJob(bookName);
      sendJson(res, 200, {
        job: job ? serializeJob(job) : null
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname.startsWith("/api/jobs/")) {
    const jobId = url.pathname.split("/").pop();
    const bookName = url.searchParams.get("bookName") || "";
    try {
      if (bookName) {
        validateBookName(bookName);
      }
      const runningJob = jobs.get(jobId);
      const job = runningJob && doesJobBelongToCurrentUser(runningJob)
        ? runningJob
        : readPersistedJobById(jobId, bookName);
      if (!job) {
        sendJson(res, 404, { error: "Job not found." });
        return;
      }
      sendJson(res, 200, runningJob && doesJobBelongToCurrentUser(runningJob) ? serializeJob(job) : job);
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/toc") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const tocPath = path.join(paths.bookRoot, "01_outline", "toc.md");

      if (!fs.existsSync(tocPath)) {
        sendJson(res, 404, { error: "toc.md not found." });
        return;
      }

      sendJson(res, 200, {
        bookName,
        tocContent: fs.readFileSync(tocPath, "utf8")
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/toc") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const tocContent = typeof body.tocContent === "string" ? body.tocContent : null;

      if (!bookName) {
        sendJson(res, 400, { error: "bookName is required." });
        return;
      }

      if (tocContent === null) {
        sendJson(res, 400, { error: "tocContent is required." });
        return;
      }

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      ensureProjectMetadataForCurrentUser(bookName, paths);
      const outlineRoot = path.join(paths.bookRoot, "01_outline");
      const tocPath = path.join(outlineRoot, "toc.md");

      ensureDir(outlineRoot);
      fs.writeFileSync(tocPath, tocContent, "utf8");

      sendJson(res, 200, {
        bookName,
        saved: true,
        tocContent
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/chapters") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const chapterRoot = path.join(paths.bookRoot, "02_chapters");
      sendJson(res, 200, {
        bookName,
        chapters: getChapterMetadata(chapterRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/chapter") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");

    if (!bookName || !fileName) {
      sendJson(res, 400, { error: "bookName and fileName are required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const chapterRoot = path.join(paths.bookRoot, "02_chapters");
      validateChapterFileName(fileName);
      const safeFileName = fileName;
      const targetPath = resolveInside(chapterRoot, safeFileName);

      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Chapter file not found." });
        return;
      }

      sendJson(res, 200, {
        bookName,
        fileName: safeFileName,
        content: fs.readFileSync(targetPath, "utf8")
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/chapter") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const fileName = body.fileName;
      const content = typeof body.content === "string" ? body.content : null;

      if (!bookName || !fileName) {
        sendJson(res, 400, { error: "bookName and fileName are required." });
        return;
      }

      if (content === null) {
        sendJson(res, 400, { error: "content is required." });
        return;
      }

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      ensureProjectMetadataForCurrentUser(bookName, paths);
      const chapterRoot = path.join(paths.bookRoot, "02_chapters");
      validateChapterFileName(fileName);
      const safeFileName = fileName;
      const targetPath = resolveInside(chapterRoot, safeFileName);

      ensureDir(chapterRoot);
      fs.writeFileSync(targetPath, content, "utf8");

      sendJson(res, 200, {
        bookName,
        fileName: safeFileName,
        saved: true,
        content
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/run-output") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");

    if (!bookName || !fileName) {
      sendJson(res, 400, { error: "bookName and fileName are required." });
      return;
    }

    try {
      validateBookName(bookName);
      validateWebRunOutputFileName(fileName);
      const safeFileName = fileName;
      const paths = getWorkspacePaths(bookName);
      const targetPath = resolveInside(paths.webRunRoot, safeFileName);

      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Run output not found." });
        return;
      }

      sendJson(res, 200, {
        bookName,
        fileName: safeFileName,
        content: fs.readFileSync(targetPath, "utf8")
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/edit-report") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const textPath = path.join(paths.logRoot, "edit_report.txt");
      const jsonPath = path.join(paths.logRoot, "edit_report.json");

      if (!fs.existsSync(textPath)) {
        sendJson(res, 404, { error: "edit_report.txt not found." });
        return;
      }

      let json = null;
      if (fs.existsSync(jsonPath)) {
        try {
          json = readJsonFile(jsonPath);
        } catch {
          json = null;
        }
      }

      sendJson(res, 200, {
        bookName,
        reportText: fs.readFileSync(textPath, "utf8"),
        reportJson: json
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-files") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const artifacts = getCoverArtifacts(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        coverArtifacts: artifacts
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-acceptance") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      sendJson(res, 200, {
        bookName,
        kdpAcceptance: getKdpAcceptanceState(paths.bookRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-acceptance-files") {
    const bookName = url.searchParams.get("bookName");
    try {
      validateBookName(bookName);
      const result = runPowerShellJson("kdp-acceptance-files.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-Action", value: "List" }
      ]);
      sendJson(res, 200, result || { bookName, files: [] });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-acceptance-file") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");
    try {
      const resolved = resolveKdpAcceptanceFilePath(bookName, fileName, [".pdf", ".png"]);
      res.writeHead(200, {
        "Content-Type": resolved.ext === ".pdf" ? "application/pdf" : "image/png",
        "Cache-Control": "no-store",
        "Content-Disposition": contentDispositionHeader(resolved.targetPath, "inline")
      });
      res.end(fs.readFileSync(resolved.targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-acceptance-pdf") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");

    if (!bookName || !fileName) {
      sendJson(res, 400, { error: "bookName and fileName are required." });
      return;
    }

    try {
      if (!/\.pdf$/i.test(fileName)) {
        throw new Error("Only PDF files can be previewed here.");
      }
      const resolved = resolveKdpAcceptanceFilePath(bookName, fileName, [".pdf"]);

      res.writeHead(200, {
        "Content-Type": "application/pdf",
        "Cache-Control": "no-store",
        "Content-Disposition": contentDispositionHeader(resolved.targetPath, "inline")
      });
      res.end(fs.readFileSync(resolved.targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-acceptance-existing-file") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const fileName = body.fileName;
      const resolved = resolveKdpAcceptanceFilePath(bookName, fileName, [".pdf", ".png"]);
      if (resolved.ext === ".png") {
        const currentSource = writeKdpCurrentSource(resolved.acceptanceRoot, buildKdpCurrentSource({
          type: "PNG",
          fileName: resolved.relativePath,
          relativePath: resolved.relativePath
        }));
        sendJson(res, 200, {
          bookName,
          fileType: "png",
          fileName: resolved.relativePath,
          currentSource,
          fileUrl: `/api/kdp-acceptance-file?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(resolved.relativePath)}`,
          kdpAcceptance: getKdpAcceptanceState(resolved.paths.bookRoot)
        });
        return;
      }

      const spec = buildKdpPaperbackCoverSpec({
        trimWidthIn: body.trimWidthIn,
        trimHeightIn: body.trimHeightIn,
        bleedIn: body.bleedIn,
        pageCount: body.pageCount,
        paperType: body.paperType
      });
      const pdfInfo = parsePdfInfo(resolved.targetPath);
      const report = buildKdpAcceptanceReport({
        bookName,
        pdfFileName: resolved.relativePath,
        pdfPath: resolved.targetPath,
        pdfInfo,
        spec
      });
      const reportPath = path.join(resolved.acceptanceRoot, "kdp_acceptance_report.json");
      const reportTextPath = path.join(resolved.acceptanceRoot, "kdp_acceptance_report.md");
      writeJsonFile(reportPath, report);
      fs.writeFileSync(reportTextPath, buildKdpAcceptanceMarkdown(report), "utf8");
      const currentSource = writeKdpCurrentSource(resolved.acceptanceRoot, buildKdpCurrentSource({
        type: "PDF",
        fileName: resolved.relativePath,
        relativePath: resolved.relativePath
      }));

      sendJson(res, 200, {
        bookName,
        fileType: "pdf",
        fileName: resolved.relativePath,
        currentSource,
        kdpAcceptance: getKdpAcceptanceState(resolved.paths.bookRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-acceptance") {
    try {
      const body = await readJsonBody(req, 120_000_000);
      const bookName = body.bookName;
      const dataUrl = typeof body.dataUrl === "string" ? body.dataUrl : "";
      const originalName = typeof body.fileName === "string" ? body.fileName : "cover-upload.pdf";

      validateBookName(bookName);
      const match = dataUrl.match(/^data:(application\/pdf|application\/octet-stream);base64,([A-Za-z0-9+/=\r\n]+)$/);
      if (!match) {
        throw new Error("Invalid PDF data.");
      }

      const buffer = Buffer.from(match[2].replace(/\s/g, ""), "base64");
      if (!buffer.length) {
        throw new Error("PDF file is empty.");
      }
      if (buffer.length > 90_000_000) {
        throw new Error("PDF file is too large for the local acceptance preview.");
      }
      if (buffer.slice(0, 5).toString("latin1") !== "%PDF-") {
        throw new Error("Uploaded file does not look like a PDF.");
      }

      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      ensureDir(acceptanceRoot);

      const safeOriginalName = sanitizeImportedPdfFileName(originalName);
      const fileName = getUniqueFileName(acceptanceRoot, safeOriginalName);
      const targetPath = resolveInside(acceptanceRoot, fileName);

      fs.writeFileSync(targetPath, buffer);
      const spec = buildKdpPaperbackCoverSpec({
        trimWidthIn: body.trimWidthIn,
        trimHeightIn: body.trimHeightIn,
        bleedIn: body.bleedIn,
        pageCount: body.pageCount,
        paperType: body.paperType,
        spineWidthIn: body.useCustomSpineWidth ? body.spineWidthIn : undefined
      });
      const pdfInfo = parsePdfInfo(targetPath);
      const report = buildKdpAcceptanceReport({
        bookName,
        pdfFileName: fileName,
        pdfPath: targetPath,
        pdfInfo,
        spec
      });
      const reportPath = path.join(acceptanceRoot, "kdp_acceptance_report.json");
      const reportTextPath = path.join(acceptanceRoot, "kdp_acceptance_report.md");
      writeJsonFile(reportPath, report);
      fs.writeFileSync(reportTextPath, buildKdpAcceptanceMarkdown(report), "utf8");
      writeKdpCurrentSource(acceptanceRoot, buildKdpCurrentSource({
        type: "PDF",
        fileName,
        relativePath: fileName,
        originalFileName: originalName
      }));

      sendJson(res, 200, {
        bookName,
        kdpAcceptance: getKdpAcceptanceState(paths.bookRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-acceptance-png") {
    try {
      const body = await readJsonBody(req, 120_000_000);
      const bookName = body.bookName;
      const dataUrl = typeof body.dataUrl === "string" ? body.dataUrl : "";
      const originalName = typeof body.fileName === "string" ? body.fileName : "cover-upload.png";

      validateBookName(bookName);
      const match = dataUrl.match(/^data:image\/png;base64,([A-Za-z0-9+/=\r\n]+)$/);
      if (!match) {
        throw new Error("Invalid PNG data.");
      }
      const buffer = Buffer.from(match[1].replace(/\s/g, ""), "base64");
      if (!buffer.length) {
        throw new Error("PNG file is empty.");
      }
      if (buffer.length > 90_000_000) {
        throw new Error("PNG file is too large for the local acceptance preview.");
      }
      if (buffer.slice(0, 8).toString("hex") !== "89504e470d0a1a0a") {
        throw new Error("Uploaded file does not look like a PNG.");
      }

      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      ensureDir(acceptanceRoot);
      const safeOriginalName = sanitizeImportedImageFileName(originalName, ".png");
      const fileName = getUniqueFileName(acceptanceRoot, safeOriginalName);
      const targetPath = resolveInside(acceptanceRoot, fileName);
      fs.writeFileSync(targetPath, buffer);
      const currentSource = writeKdpCurrentSource(acceptanceRoot, buildKdpCurrentSource({
        type: "PNG",
        fileName,
        relativePath: fileName,
        originalFileName: originalName
      }));

      sendJson(res, 200, {
        bookName,
        fileType: "png",
        fileName,
        currentSource,
        fileUrl: `/api/kdp-acceptance-file?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(fileName)}`,
        kdpAcceptance: getKdpAcceptanceState(paths.bookRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-llm-text-regions") {
    try {
      const body = await readJsonBody(req, 80_000_000);
      const bookName = body.bookName;
      const imageDataUrl = typeof body.imageDataUrl === "string" ? body.imageDataUrl : "";
      const sourceRelativePath = typeof body.sourceRelativePath === "string" ? body.sourceRelativePath : "";
      let imageWidth = Math.round(Number(body.imageWidth || 0));
      let imageHeight = Math.round(Number(body.imageHeight || 0));
      const model = typeof body.model === "string" && body.model.trim() ? body.model.trim() : "gpt-5.2";

      validateBookName(bookName);
      if (!process.env.OPENAI_API_KEY) {
        throw new Error("OPENAI_API_KEY not set.");
      }
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const visionRoot = path.join(acceptanceRoot, "llm_text_regions");
      ensureDir(visionRoot);
      const stamp = formatCompactFileStamp();
      let imageBuffer = null;
      let sourcePath = "";
      let imageFileName = "";
      if (sourceRelativePath) {
        const resolved = resolveKdpAcceptanceFilePath(bookName, sourceRelativePath, [".png"]);
        sourcePath = resolved.targetPath;
        imageBuffer = fs.readFileSync(sourcePath);
        const dimensions = getPngDimensions(imageBuffer);
        imageWidth = dimensions.width;
        imageHeight = dimensions.height;
        imageFileName = getUniqueFileName(visionRoot, `llm-${path.basename(resolved.relativePath)}`);
      } else {
        if (!/^data:image\/png;base64,[A-Za-z0-9+/=\r\n]+$/.test(imageDataUrl)) {
          throw new Error("imageDataUrl must be a PNG data URL unless sourceRelativePath is provided.");
        }
        imageBuffer = Buffer.from(imageDataUrl.replace(/^data:image\/png;base64,/, "").replace(/\s/g, ""), "base64");
        const dimensions = getPngDimensions(imageBuffer);
        imageWidth = imageWidth || dimensions.width;
        imageHeight = imageHeight || dimensions.height;
        imageFileName = `kdp-llm-text-${stamp}.png`;
      }
      if (imageWidth < 100 || imageHeight < 100) {
        throw new Error("imageWidth and imageHeight are required.");
      }
      const baseFileName = path.basename(imageFileName, ".png");
      const resultFileName = `${baseFileName}.json`;
      const latestFileName = "latest_llm_text_regions.json";
      const imagePath = path.join(visionRoot, imageFileName);
      const resultPath = path.join(visionRoot, resultFileName);
      const latestPath = path.join(visionRoot, latestFileName);
      fs.writeFileSync(imagePath, imageBuffer);
      const llmImageDataUrl = `data:image/png;base64,${imageBuffer.toString("base64")}`;

      const prompt = [
        "You are inspecting a flattened PNG render of a KDP paperback full-cover PDF.",
        `The PNG size is ${imageWidth} x ${imageHeight} pixels. The coordinate origin is the top-left corner.`,
        "Your only task is to detect visible text regions and return their full pixel bounding boxes.",
        "Do not classify regions as front/back/spine. Do not crop, clamp, or force a text box into any book area. If text crosses a fold, trim, margin, or panel boundary, return the full bounding box that covers the visible text.",
        "Ignore stars, dots, guide lines, light rays, decorative borders, book art, barcode lines, and non-text ornaments.",
        "Return bounding boxes for coherent text blocks, not every tiny speck. Split by natural text blocks: title, subtitle, author, spine title, publisher/logo text, back-cover paragraphs.",
        "Coordinates must be pixel coordinates in the provided PNG, origin at top-left, x/y/width/height integers.",
        "Use notes to state whether the text appears on the front cover, book spine, or back cover when visually clear.",
        "Return JSON only with this schema:",
        '{"image":{"width":number,"height":number},"regions":[{"id":"string","text":"visible text if readable","x":number,"y":number,"width":number,"height":number,"confidence":0-1,"orientation":"horizontal|vertical|rotated|unknown","notes":"front cover|book spine|back cover + short detail"}]}'
      ].join("\n");

      const response = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${process.env.OPENAI_API_KEY}`,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          model,
          input: [
            {
              role: "user",
              content: [
                { type: "input_text", text: prompt },
                { type: "input_image", image_url: llmImageDataUrl }
              ]
            }
          ]
        })
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`OpenAI vision request failed (${response.status}): ${errorText.slice(0, 500)}`);
      }

      const responseJson = await response.json();
      const modelText = extractResponseText(responseJson);
      const parsed = parseJsonFromModelText(modelText);
      const modelImageWidth = Math.max(1, Math.round(Number(parsed?.image?.width || imageWidth)));
      const modelImageHeight = Math.max(1, Math.round(Number(parsed?.image?.height || imageHeight)));
      const coordinateScale = {
        x: imageWidth / modelImageWidth,
        y: imageHeight / modelImageHeight
      };
      const regions = (Array.isArray(parsed.regions) ? parsed.regions : [])
        .map((region, index) => normalizeVisionRegion(region, index, imageWidth, imageHeight, coordinateScale))
        .filter((region) => region.width > 0 && region.height > 0);
      const savedResult = {
        bookName,
        createdAt: formatLocalTimestamp(),
        model,
        prompt,
        image: {
          width: imageWidth,
          height: imageHeight,
          fileName: imageFileName,
          path: imagePath,
          bytes: imageBuffer.length,
          sourcePath,
          sourceRelativePath: sourceRelativePath || ""
        },
        modelImage: {
          width: modelImageWidth,
          height: modelImageHeight
        },
        coordinateScale,
        regions,
        parsed,
        rawText: modelText,
        usage: responseJson.usage || null,
        responseId: responseJson.id || "",
        responseCreatedAt: responseJson.created_at || null,
        responseStatus: responseJson.status || "",
        rawResponse: responseJson
      };
      writeJsonFile(resultPath, savedResult);
      writeJsonFile(latestPath, savedResult);
      appendJsonLine(path.join(visionRoot, "llm_text_regions_runs.jsonl"), {
        bookName,
        createdAt: savedResult.createdAt,
        model,
        resultFileName,
        imageFileName,
        image: savedResult.image,
        modelImage: savedResult.modelImage,
        coordinateScale,
        regionCount: regions.length,
        usage: savedResult.usage
      });
      const billing = recordUserTokenUsage(getCurrentUserContext().id, {
        usage: responseJson.usage || null,
        source: "kdp_llm_text_regions",
        route: "kdp-llm-text-regions",
        bookName,
        model
      });

      sendJson(res, 200, {
        bookName,
        model,
        image: {
          width: imageWidth,
          height: imageHeight
        },
        modelImage: {
          width: modelImageWidth,
          height: modelImageHeight
        },
        coordinateScale,
        regions,
        rawText: modelText,
        usage: responseJson.usage || null,
        billing,
        responseId: responseJson.id || "",
        responseStatus: responseJson.status || "",
        createdAt: savedResult.createdAt,
        saved: {
          resultFileName,
          imageFileName,
          latestFileName,
          resultRelativePath: `07_cover/kdp_acceptance/llm_text_regions/${resultFileName}`,
          imageRelativePath: `07_cover/kdp_acceptance/llm_text_regions/${imageFileName}`,
          latestRelativePath: `07_cover/kdp_acceptance/llm_text_regions/${latestFileName}`,
          resultPath,
          imagePath,
          latestPath
        }
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-fix-report") {
    try {
      const body = await readJsonBody(req, 10_000_000);
      const bookName = body.bookName;
      const reportText = typeof body.reportText === "string" ? body.reportText : "";
      const spec = body.spec && typeof body.spec === "object" ? body.spec : null;
      const source = body.source && typeof body.source === "object" ? body.source : {};
      const textRegionCount = Math.max(0, Math.round(Number(body.textRegionCount || 0)));

      validateBookName(bookName);
      if (!reportText.trim()) {
        throw new Error("reportText is required.");
      }

      const paths = getWorkspacePaths(bookName);
      const reportRoot = path.join(getKdpAcceptanceRoot(paths.bookRoot), "fix_reports");
      const backupRoot = path.join(reportRoot, "back");
      ensureDir(reportRoot);
      ensureDir(backupRoot);

      const createdAtDate = new Date();
      const createdAt = formatLocalTimestamp(createdAtDate);
      const stamp = formatCompactFileStamp(createdAtDate);
      const baseFileName = `kdp-fix-report-${stamp}`;
      const textFileName = `${baseFileName}.md`;
      const resultFileName = `${baseFileName}.json`;
      const textPath = path.join(reportRoot, textFileName);
      const resultPath = path.join(reportRoot, resultFileName);
      const latestTextPath = path.join(reportRoot, "latest_kdp_fix_report.md");
      const latestJsonPath = path.join(reportRoot, "latest_kdp_fix_report.json");
      const backups = [];

      if (fs.existsSync(latestTextPath)) {
        const backupTextName = `latest_kdp_fix_report.back-${stamp}.md`;
        const backupTextPath = path.join(backupRoot, backupTextName);
        fs.copyFileSync(latestTextPath, backupTextPath);
        backups.push({ type: "text", fileName: backupTextName, path: backupTextPath });
      }
      if (fs.existsSync(latestJsonPath)) {
        const backupJsonName = `latest_kdp_fix_report.back-${stamp}.json`;
        const backupJsonPath = path.join(backupRoot, backupJsonName);
        fs.copyFileSync(latestJsonPath, backupJsonPath);
        backups.push({ type: "json", fileName: backupJsonName, path: backupJsonPath });
      }

      const savedReportText = formatKdpFixReportWithHeader(reportText, { createdAt, bookName, source });
      const savedResult = {
        bookName,
        createdAt,
        reportText: savedReportText,
        spec,
        source,
        textRegionCount,
        saved: {
          resultFileName,
          textFileName,
          latestFileName: "latest_kdp_fix_report.json",
          latestTextFileName: "latest_kdp_fix_report.md",
          resultPath,
          textPath,
          latestPath: latestJsonPath,
          latestTextPath,
          backupDir: backupRoot,
          backups
        }
      };

      fs.writeFileSync(textPath, savedReportText, "utf8");
      writeJsonFile(resultPath, savedResult);
      fs.writeFileSync(latestTextPath, savedReportText, "utf8");
      writeJsonFile(latestJsonPath, savedResult);
      appendJsonLine(path.join(reportRoot, "kdp_fix_report_runs.jsonl"), {
        bookName,
        createdAt: savedResult.createdAt,
        resultFileName,
        textFileName,
        source,
        textRegionCount,
        backups: backups.map((backup) => backup.fileName)
      });

      sendJson(res, 200, {
        bookName,
        fixReport: getKdpLatestFixReportState(getKdpAcceptanceRoot(paths.bookRoot)),
        saved: savedResult.saved
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-fix-workbench/prepare") {
    try {
      const body = await readJsonBody(req, 80_000_000);
      const bookName = body.bookName;
      const imageDataUrl = typeof body.imageDataUrl === "string" ? body.imageDataUrl : "";
      const prompt = typeof body.prompt === "string" ? body.prompt : "";
      const model = typeof body.model === "string" && body.model.trim() ? body.model.trim() : "gpt-image-1.5";
      const imageWidth = Math.round(Number(body.imageWidth || 0));
      const imageHeight = Math.round(Number(body.imageHeight || 0));

      validateBookName(bookName);
      if (!/^data:image\/png;base64,[A-Za-z0-9+/=\r\n]+$/.test(imageDataUrl)) {
        throw new Error("imageDataUrl must be a PNG data URL.");
      }
      if (!prompt.trim()) {
        throw new Error("prompt is required.");
      }
      if (imageWidth < 100 || imageHeight < 100) {
        throw new Error("imageWidth and imageHeight are required.");
      }

      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const workRoot = getKdpFixWorkbenchRoot(acceptanceRoot);
      const sourceRoot = path.join(workRoot, "source");
      const promptRoot = path.join(workRoot, "prompts");
      ensureDir(sourceRoot);
      ensureDir(promptRoot);
      const stamp = formatCompactFileStamp();
      const sourceFileName = `kdp-fix-source-${stamp}.png`;
      const promptFileName = `kdp-fix-prompt-${stamp}.txt`;
      const sourcePath = path.join(sourceRoot, sourceFileName);
      const promptPath = path.join(promptRoot, promptFileName);
      const imageBuffer = Buffer.from(imageDataUrl.replace(/^data:image\/png;base64,/, "").replace(/\s/g, ""), "base64");
      fs.writeFileSync(sourcePath, imageBuffer);
      fs.writeFileSync(promptPath, prompt, "utf8");

      const statePath = path.join(workRoot, "workbench_state.json");
      const existing = readJsonFileSafe(statePath) || {};
      const nextState = {
        ...existing,
        updatedAt: formatLocalTimestamp(),
        model,
        sourceFileName,
        sourcePath,
        sourceImage: {
          width: imageWidth,
          height: imageHeight,
          bytes: imageBuffer.length
        },
        promptFileName,
        promptPath,
        prompt
      };
      writeJsonFile(statePath, nextState);
      const currentSource = writeKdpCurrentSource(acceptanceRoot, buildKdpCurrentSource({
        type: "PNG",
        directory: "07_cover/kdp_acceptance",
        fileName: `fix_workbench/source/${sourceFileName}`,
        relativePath: `fix_workbench/source/${sourceFileName}`
      }));
      sendJson(res, 200, {
        bookName,
        prepared: true,
        currentSource,
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/crop") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const sourceFileName = typeof body.sourceFileName === "string" ? body.sourceFileName : "";
      const x = Math.round(Number(body.x));
      const y = Math.round(Number(body.y));
      const width = Math.round(Number(body.width));
      const height = Math.round(Number(body.height));

      validateBookName(bookName);
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height)) {
        throw new Error("x, y, width, and height are required numbers.");
      }
      if (x < 0 || y < 0 || width <= 0 || height <= 0) {
        throw new Error("x/y must be >= 0 and width/height must be > 0.");
      }

      const result = runPowerShellJson("kdp-crop-image-region.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-SourceFile", value: sourceFileName || undefined },
        { flag: "-X", value: x },
        { flag: "-Y", value: y },
        { flag: "-Width", value: width },
        { flag: "-Height", value: height },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        crop: result,
        cropImageUrl: result?.outputFileName
          ? `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=crop&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/resize") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const inputFileName = typeof body.inputFileName === "string" ? body.inputFileName : "";
      const scalePercent = Number(body.scalePercent);

      validateBookName(bookName);
      if (!Number.isFinite(scalePercent) || scalePercent <= 1 || scalePercent > 400) {
        throw new Error("scalePercent must be > 1 and <= 400.");
      }

      const result = runPowerShellJson("kdp-resize-image-region.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-InputFile", value: inputFileName || undefined },
        { flag: "-ScalePercent", value: scalePercent },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        resize: result,
        crop: result,
        cropImageUrl: result?.outputFileName
          ? `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=crop&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/state") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const uiState = body.uiState && typeof body.uiState === "object" ? body.uiState : {};
      validateBookName(bookName);

      const cleanNumber = (value, fallback = "") => {
        if (value === "" || value === null || value === undefined) return fallback;
        const number = Math.round(Number(value));
        return Number.isFinite(number) ? number : fallback;
      };
      const cleanColor = (value, fallback = "#07121b") => {
        const text = String(value || "").trim();
        return /^#[0-9a-fA-F]{6}$/.test(text) ? text : fallback;
      };
      const cleanPreset = String(uiState.fill?.preset || "").trim();
      const cleanMode = String(uiState.fill?.mode || "Auto").trim();
      const nextUiState = {
        updatedAt: formatLocalTimestamp(),
        crop: {
          x: cleanNumber(uiState.crop?.x),
          y: cleanNumber(uiState.crop?.y),
          width: cleanNumber(uiState.crop?.width),
          height: cleanNumber(uiState.crop?.height)
        },
        fill: {
          color: cleanColor(uiState.fill?.color),
          preset: /^#[0-9a-fA-F]{6}$/.test(cleanPreset) || cleanPreset === "custom" ? cleanPreset : "#07121b",
          mode: cleanMode === "Solid" ? "Solid" : "Auto"
        },
        composite: {
          x: cleanNumber(uiState.composite?.x),
          y: cleanNumber(uiState.composite?.y)
        },
        resize: {
          scalePercent: cleanNumber(uiState.resize?.scalePercent, 95)
        }
      };

      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const workRoot = getKdpFixWorkbenchRoot(acceptanceRoot);
      ensureDir(workRoot);
      const statePath = path.join(workRoot, "workbench_state.json");
      const existing = readJsonFileSafe(statePath) || {};
      writeJsonFile(statePath, {
        ...existing,
        updatedAt: nextUiState.updatedAt,
        imgBlackUi: nextUiState
      });
      sendJson(res, 200, {
        bookName,
        imgBlackUi: nextUiState,
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/fill") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const sourceFileName = typeof body.sourceFileName === "string" ? body.sourceFileName : "";
      const fillColor = typeof body.fillColor === "string" ? body.fillColor : "#07121b";
      const fillMode = body.fillMode === "Solid" ? "Solid" : "Auto";
      const x = Math.round(Number(body.x));
      const y = Math.round(Number(body.y));
      const width = Math.round(Number(body.width));
      const height = Math.round(Number(body.height));

      validateBookName(bookName);
      if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height)) {
        throw new Error("x, y, width, and height are required numbers.");
      }
      if (x < 0 || y < 0 || width <= 0 || height <= 0) {
        throw new Error("x/y must be >= 0 and width/height must be > 0.");
      }
      if (!/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(fillColor)) {
        throw new Error("fillColor must be a hex color like #07121b.");
      }

      const result = runPowerShellJson("kdp-fill-image-region.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-SourceFile", value: sourceFileName || undefined },
        { flag: "-X", value: x },
        { flag: "-Y", value: y },
        { flag: "-Width", value: width },
        { flag: "-Height", value: height },
        { flag: "-FillColor", value: fillColor },
        { flag: "-FillMode", value: fillMode },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        fill: result,
        fillImageUrl: result?.outputFileName
          ? `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=fill&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/composite") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const baseFileName = typeof body.baseFileName === "string" ? body.baseFileName : "";
      const overlayFileName = typeof body.overlayFileName === "string" ? body.overlayFileName : "";
      const x = Math.round(Number(body.x));
      const y = Math.round(Number(body.y));

      validateBookName(bookName);
      if (!Number.isFinite(x) || !Number.isFinite(y)) {
        throw new Error("x and y are required numbers.");
      }
      if (x < 0 || y < 0) {
        throw new Error("x/y must be >= 0.");
      }

      const result = runPowerShellJson("kdp-composite-image-region.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-BaseFile", value: baseFileName || undefined },
        { flag: "-OverlayFile", value: overlayFileName || undefined },
        { flag: "-X", value: x },
        { flag: "-Y", value: y },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        composite: result,
        compositeImageUrl: result?.outputFileName
          ? `/api/kdp-fix-image?bookName=${encodeURIComponent(bookName)}&kind=composite&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/kdp-img-black/png-to-pdf") {
    try {
      const body = await readJsonBody(req, 1_000_000);
      const bookName = body.bookName;
      const inputFileName = typeof body.inputFileName === "string" ? body.inputFileName : "";
      validateBookName(bookName);

      const result = runPowerShellJson("kdp-png-to-pdf.ps1", [
        { flag: "-BookName", value: bookName },
        { flag: "-InputFile", value: inputFileName || undefined },
        { flag: "-Force", type: "switch", enabled: Boolean(body.force) }
      ]);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      sendJson(res, 200, {
        bookName,
        pdf: result,
        pdfUrl: result?.outputFileName
          ? `/api/kdp-fix-pdf?bookName=${encodeURIComponent(bookName)}&fileName=${encodeURIComponent(result.outputFileName)}&t=${Date.now()}`
          : "",
        fixWorkbench: getKdpFixWorkbenchState(acceptanceRoot)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-fix-pdf") {
    const bookName = url.searchParams.get("bookName");
    const fileName = url.searchParams.get("fileName");
    try {
      validateBookName(bookName);
      const safeFileName = sanitizeKdpFixPdfFileName(fileName);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const targetRoot = path.join(getKdpFixWorkbenchRoot(acceptanceRoot), "pdfs");
      const targetPath = resolveInside(targetRoot, safeFileName);
      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "KDP fix PDF not found." });
        return;
      }
      res.writeHead(200, {
        "Content-Type": "application/pdf",
        "Cache-Control": "no-store",
        "Content-Disposition": contentDispositionHeader(targetPath, "inline")
      });
      res.end(fs.readFileSync(targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/kdp-fix-image") {
    const bookName = url.searchParams.get("bookName");
    const kind = url.searchParams.get("kind");
    const fileName = url.searchParams.get("fileName");
    try {
      validateBookName(bookName);
      if (!["source", "output", "crop", "fill", "composite"].includes(kind || "")) {
        throw new Error("kind must be source, output, crop, fill, or composite.");
      }
      const safeFileName = sanitizeKdpFixImageFileName(fileName);
      const paths = getWorkspacePaths(bookName);
      const acceptanceRoot = getKdpAcceptanceRoot(paths.bookRoot);
      const kindFolder = kind === "crop" ? "crops" : kind === "fill" ? "fills" : kind === "composite" ? "composites" : kind;
      const targetRoot = path.join(getKdpFixWorkbenchRoot(acceptanceRoot), kindFolder);
      const targetPath = resolveInside(targetRoot, safeFileName);
      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "KDP fix image not found." });
        return;
      }
      res.writeHead(200, {
        "Content-Type": getImageMimeTypeByPath(targetPath),
        "Cache-Control": "no-store",
        "Content-Disposition": contentDispositionHeader(targetPath, "inline")
      });
      res.end(fs.readFileSync(targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-copy") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);

      if (!fs.existsSync(paths.coverCopyJsonPath)) {
        sendJson(res, 404, { error: "cover_copy.json not found." });
        return;
      }

      const copyJson = readJsonFile(paths.coverCopyJsonPath);
      const copyMarkdown = fs.existsSync(paths.coverCopyMdPath)
        ? fs.readFileSync(paths.coverCopyMdPath, "utf8")
        : buildCoverCopyMarkdown(copyJson);

      sendJson(res, 200, {
        bookName,
        copyJson,
        copyMarkdown
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-midjourney-prompt") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      validateBookName(bookName);

      const paths = getWorkspacePaths(bookName);
      const prompt = buildCoverMidjourneyPrompt(paths, {
        title: body.title,
        subtitle: body.subtitle,
        author: body.author
      });

      sendJson(res, 200, { bookName, prompt });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-midjourney-prompt-result") {
    const bookName = url.searchParams.get("bookName");
    const edition = url.searchParams.get("edition") || "ebook";

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }

      const paths = getWorkspacePaths(bookName);
      const promptRoot = path.join(paths.bookRoot, "07_cover", "next", edition, "prompts");
      const promptPath = path.join(promptRoot, "midjourney_prompt.txt");
      const reportJsonPath = path.join(promptRoot, "midjourney_prompt_report.json");
      const reportMdPath = path.join(promptRoot, "midjourney_prompt_report.md");

      if (!fs.existsSync(promptPath)) {
        sendJson(res, 404, { error: "midjourney_prompt.txt not found." });
        return;
      }

      sendJson(res, 200, {
        bookName,
        edition,
        prompt: fs.readFileSync(promptPath, "utf8").replace(/^\uFEFF/, ""),
        reportText: readTextIfExists(reportMdPath),
        reportJson: readJsonFileSafe(reportJsonPath),
        paths: {
          prompt: promptPath,
          report: reportMdPath,
          reportJson: reportJsonPath
        }
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-workbench-state") {
    const bookName = url.searchParams.get("bookName");
    const edition = url.searchParams.get("edition") || "ebook";

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }
      const paths = getWorkspacePaths(bookName);
      sendJson(res, 200, {
        bookName,
        workbench: getCoverWorkbenchState(paths.bookRoot, edition)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-workbench-state") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const edition = body.nextEdition || body.edition || "ebook";
      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }

      const paths = getWorkspacePaths(bookName);
      const nextRoot = path.join(paths.bookRoot, "07_cover", "next", edition);
      const importRoot = path.join(nextRoot, "imports");
      const statePath = path.join(nextRoot, "workbench_state.json");
      const existingState = readJsonFileSafe(statePath) || {};
      const nextState = {
        ...existingState,
        updated_at: formatLocalTimestamp()
      };

      if (typeof body.selectedImportFile === "string" && body.selectedImportFile.trim()) {
        const selectedImportFile = path.basename(body.selectedImportFile.trim());
        validateAssetFileName(selectedImportFile);
        if (!/\.(png|jpg|jpeg|webp)$/i.test(selectedImportFile)) {
          throw new Error("Selected import must be an image file.");
        }
        const selectedPath = resolveInside(importRoot, selectedImportFile);
        if (!fs.existsSync(selectedPath)) {
          throw new Error("Selected import image not found.");
        }
        nextState.selected_import_file = selectedImportFile;
        nextState.latest_import_file = selectedImportFile;
        nextState.latest_import_path = selectedPath;
      }

      ["editText", "publisher", "imageModel"].forEach((key) => {
        if (typeof body[key] === "string") {
          const stateKey = key === "editText" ? "edit_text" : key === "imageModel" ? "image_model" : key;
          nextState[stateKey] = body[key];
        }
      });

      writeJsonFile(statePath, nextState);
      sendJson(res, 200, {
        bookName,
        workbench: getCoverWorkbenchState(paths.bookRoot, edition)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-midjourney-prompt/save") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const edition = body.nextEdition || body.edition || "ebook";
      const prompt = typeof body.prompt === "string" ? body.prompt : "";
      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }
      if (!prompt.trim()) {
        throw new Error("Prompt is empty.");
      }

      const paths = getWorkspacePaths(bookName);
      ensureDir(paths.coverBriefRoot);
      const promptPath = path.join(paths.coverBriefRoot, "cover_midjourney_prompt.txt");
      const nextPromptPath = path.join(paths.bookRoot, "07_cover", "next", edition, "prompts", "midjourney_prompt.txt");
      ensureDir(path.dirname(nextPromptPath));
      fs.writeFileSync(promptPath, prompt, "utf8");
      fs.writeFileSync(nextPromptPath, prompt, "utf8");
      const statePath = path.join(paths.bookRoot, "07_cover", "next", edition, "workbench_state.json");
      const existingState = readJsonFileSafe(statePath) || {};
      writeJsonFile(statePath, {
        ...existingState,
        updated_at: formatLocalTimestamp(),
        midjourney_prompt_file: nextPromptPath
      });

      sendJson(res, 200, {
        bookName,
        edition,
        fileName: "cover_midjourney_prompt.txt",
        path: promptPath,
        nextPath: nextPromptPath,
        prompt
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-base-image/import") {
    try {
      const body = await readJsonBody(req, 40_000_000);
      const bookName = body.bookName;
      const edition = body.nextEdition || body.edition || "ebook";
      const dataUrl = typeof body.dataUrl === "string" ? body.dataUrl : "";
      const originalName = typeof body.fileName === "string" ? body.fileName : "";

      validateBookName(bookName);
      if (!["ebook", "print"].includes(edition)) {
        throw new Error("Invalid edition.");
      }

      const match = dataUrl.match(/^data:(image\/png|image\/jpeg|image\/webp);base64,([A-Za-z0-9+/=\r\n]+)$/);
      if (!match) {
        throw new Error("Invalid image data.");
      }

      const mimeType = match[1];
      const fallbackExt = {
        "image/png": ".png",
        "image/jpeg": ".jpg",
        "image/webp": ".webp"
      }[mimeType];
      const safeOriginalName = sanitizeImportedImageFileName(originalName, fallbackExt);
      const stamp = formatFileStamp();
      const buffer = Buffer.from(match[2].replace(/\s/g, ""), "base64");
      if (!buffer.length) {
        throw new Error("Image file is empty.");
      }
      if (buffer.length > 30_000_000) {
        throw new Error("Image file is too large.");
      }

      const paths = getWorkspacePaths(bookName);
      const importRoot = path.join(paths.bookRoot, "07_cover", "next", edition, "imports");
      ensureDir(importRoot);
      let fileName = `imported-base-${stamp}-${safeOriginalName}`;
      let targetPath = resolveInside(importRoot, fileName);
      let suffix = 2;
      while (fs.existsSync(targetPath)) {
        const ext = path.extname(fileName);
        const stem = path.basename(fileName, ext);
        fileName = `${stem}-${suffix}${ext}`;
        targetPath = resolveInside(importRoot, fileName);
        suffix += 1;
      }

      fs.writeFileSync(targetPath, buffer);
      const statePath = path.join(paths.bookRoot, "07_cover", "next", edition, "workbench_state.json");
      const existingState = readJsonFileSafe(statePath) || {};
      writeJsonFile(statePath, {
        ...existingState,
        updated_at: formatLocalTimestamp(),
        latest_import_file: fileName,
        selected_import_file: fileName,
        latest_import_path: targetPath
      });
      sendJson(res, 200, {
        bookName,
        edition,
        fileName,
        mimeType,
        size: buffer.length,
        path: targetPath,
        section: "next-imports"
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-assistant-result") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);

      if (!fs.existsSync(paths.coverAssistantJsonPath)) {
        sendJson(res, 404, { error: "cover_assistant_last.json not found." });
        return;
      }

      const assistantResult = readJsonFile(paths.coverAssistantJsonPath);
      const responseMarkdown = fs.existsSync(paths.coverAssistantMdPath)
        ? fs.readFileSync(paths.coverAssistantMdPath, "utf8")
        : getStringValue(assistantResult.response);

      sendJson(res, 200, {
        bookName,
        assistantResult,
        responseMarkdown
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/cover-copy") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const selected = body.selected || {};
      const candidates = body.candidates || {};
      const editorNotes = Array.isArray(body.editorNotes) ? body.editorNotes : [];

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);

      if (!fs.existsSync(paths.coverCopyJsonPath)) {
        sendJson(res, 404, { error: "cover_copy.json not found." });
        return;
      }

      const existing = readJsonFile(paths.coverCopyJsonPath);
      const nextData = {
        ...existing,
        selected: {
          ...(existing.selected || {}),
          subtitle: String(selected.subtitle || ""),
          back_cover_hook: String(selected.back_cover_hook || ""),
          obi_copy: String(selected.obi_copy || ""),
          marketing_tagline: String(selected.marketing_tagline || ""),
          back_cover_blurb: String(selected.back_cover_blurb || ""),
          author_bio: String(selected.author_bio || ""),
          spine_text: String(selected.spine_text || "")
        },
        candidates: {
          ...(existing.candidates || {}),
          subtitle: Array.isArray(candidates.subtitle) ? candidates.subtitle : (existing.candidates?.subtitle || []),
          back_cover_hook: Array.isArray(candidates.back_cover_hook) ? candidates.back_cover_hook : (existing.candidates?.back_cover_hook || []),
          obi_copy: Array.isArray(candidates.obi_copy) ? candidates.obi_copy : (existing.candidates?.obi_copy || []),
          marketing_tagline: Array.isArray(candidates.marketing_tagline) ? candidates.marketing_tagline : (existing.candidates?.marketing_tagline || [])
        },
        editor_notes: editorNotes.map((item) => String(item || "")).filter(Boolean)
      };

      fs.writeFileSync(paths.coverCopyJsonPath, `${JSON.stringify(nextData, null, 2)}\n`, "utf8");
      fs.writeFileSync(paths.coverCopyMdPath, buildCoverCopyMarkdown(nextData), "utf8");

      sendJson(res, 200, {
        bookName,
        saved: true,
        copyJson: nextData,
        copyMarkdown: buildCoverCopyMarkdown(nextData)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/frontmatter") {
    const bookName = url.searchParams.get("bookName");

    if (!bookName) {
      sendJson(res, 400, { error: "bookName is required." });
      return;
    }

    try {
      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      sendJson(res, 200, {
        bookName,
        frontmatter: getFrontmatterPayload(paths)
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/frontmatter") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const coverPage = typeof body.coverPage === "string" ? body.coverPage : null;
      const titlePage = typeof body.titlePage === "string" ? body.titlePage : null;
      const copyrightPage = typeof body.copyrightPage === "string" ? body.copyrightPage : null;

      if (!bookName) {
        sendJson(res, 400, { error: "bookName is required." });
        return;
      }

      if (coverPage === null || titlePage === null || copyrightPage === null) {
        sendJson(res, 400, { error: "coverPage, titlePage, and copyrightPage are required." });
        return;
      }

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);

      ensureDir(paths.frontmatterBaseRoot);
      ensureDir(paths.frontmatterRoot);

      fs.writeFileSync(paths.coverPagePath, coverPage, "utf8");
      fs.writeFileSync(paths.titlePagePath, titlePage, "utf8");
      fs.writeFileSync(paths.copyrightPagePath, copyrightPage, "utf8");

      let manifest = null;
      if (fs.existsSync(paths.frontmatterManifestPath)) {
        try {
          manifest = readJsonFile(paths.frontmatterManifestPath);
        } catch {
          manifest = null;
        }
      }

      const nextManifest = {
        ...(manifest || {}),
        generated_at: formatLocalTimestamp(),
        book_name: bookName,
        edition: "ebook",
        files: [
          { role: "cover_page", file: "cover_page.md", path: paths.coverPagePath },
          { role: "title_page", file: "title_page.md", path: paths.titlePagePath },
          { role: "copyright_page", file: "copyright_page.md", path: paths.copyrightPagePath }
        ]
      };

      fs.writeFileSync(paths.frontmatterManifestPath, `${JSON.stringify(nextManifest, null, 2)}\n`, "utf8");

      sendJson(res, 200, {
        bookName,
        saved: true,
        frontmatter: {
          manifest: nextManifest,
          coverPage,
          titlePage,
          copyrightPage
        }
      });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET" && url.pathname === "/api/cover-image") {
    const bookName = url.searchParams.get("bookName");
    const section = url.searchParams.get("section");
    const fileName = url.searchParams.get("fileName");

    if (!bookName || !section || !fileName) {
      sendJson(res, 400, { error: "bookName, section, and fileName are required." });
      return;
    }

    try {
      validateBookName(bookName);
      validateAssetFileName(fileName);
      const paths = getWorkspacePaths(bookName);
      const sectionRoot = resolveCoverSectionRoot(paths, section);
      const safeFileName = fileName;
      const targetPath = resolveInside(sectionRoot, safeFileName);
      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Cover asset not found." });
        return;
      }

      const ext = path.extname(targetPath).toLowerCase();
      const mime = {
        ".png": "image/png",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".webp": "image/webp",
        ".pdf": "application/pdf"
      }[ext] || "application/octet-stream";

      res.writeHead(200, {
        "Content-Type": mime,
        "Cache-Control": "no-store",
        "Content-Disposition": contentDispositionHeader(targetPath, "inline")
      });
      res.end(fs.readFileSync(targetPath));
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/open-cover-folder") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const section = body.section;

      validateBookName(bookName);
      const paths = getWorkspacePaths(bookName);
      const sectionRoot = resolveCoverSectionRoot(paths, section);
      if (!fs.existsSync(sectionRoot)) {
        sendJson(res, 404, { error: "Cover folder not found." });
        return;
      }

      if (isCloudMode()) {
        sendJson(res, 200, cloudFolderPayload({ bookName, section }, sectionRoot));
        return;
      }

      openFolder(sectionRoot);
      sendJson(res, 200, { opened: true, cloudMode: false, mode: APP_MODE, bookName, section, path: sectionRoot });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/api/reveal-cover-file") {
    try {
      const body = await readJsonBody(req);
      const bookName = body.bookName;
      const section = body.section;
      const fileName = body.fileName;

      validateBookName(bookName);
      validateAssetFileName(fileName);
      const paths = getWorkspacePaths(bookName);
      const sectionRoot = resolveCoverSectionRoot(paths, section);
      const targetPath = resolveInside(sectionRoot, fileName);
      if (!fs.existsSync(targetPath)) {
        sendJson(res, 404, { error: "Cover file not found." });
        return;
      }

      if (isCloudMode()) {
        sendJson(res, 200, cloudFilePayload({
          bookName,
          section,
          fileName
        }, targetPath, withQuery("/api/cover-image", { bookName, section, fileName })));
        return;
      }

      revealFileInExplorer(targetPath);
      sendJson(res, 200, { opened: true, cloudMode: false, mode: APP_MODE, bookName, section, fileName, path: targetPath });
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "POST" && url.pathname.startsWith("/api/run/")) {
    const route = url.pathname.split("/").pop();
    try {
      const body = await readJsonBody(req);
      await handleRun(route, body, res);
    } catch (error) {
      sendJson(res, 400, { error: error.message });
    }
    return;
  }

  if (req.method === "GET") {
    serveStatic(url.pathname, res);
    return;
  }

  sendJson(res, 405, { error: "Method not allowed." });
});

server.listen(PORT, HOST, () => {
  console.log(`SageWrite Web UI running at http://${HOST}:${PORT}`);
});
