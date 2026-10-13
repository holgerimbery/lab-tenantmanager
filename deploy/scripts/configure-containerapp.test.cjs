const { test } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");

const script = readFileSync(join(__dirname, "configure-containerapp.ps1"), "utf8");

test("retrieves the Cosmos primary key from the account, not a placeholder", () => {
  assert.match(script, /cosmosdb",\s*"keys",\s*"list"/);
  assert.match(script, /"--query",\s*"primaryMasterKey"/);
  assert.match(script, /"cosmos-key=\$cosmosKey"/);
});

test("wires COSMOS_KEY and the auth secrets as secret references", () => {
  assert.match(script, /"COSMOS_KEY=secretref:cosmos-key"/);
  assert.match(script, /"AZURE_AD_CLIENT_SECRET=secretref:ad-client-secret"/);
  assert.match(script, /"NEXTAUTH_SECRET=secretref:nextauth-secret"/);
  assert.match(script, /"AUTH_SECRET=secretref:auth-secret"/);
});

test("sets the master-admin allow-list so /admin is reachable", () => {
  assert.match(script, /\$MasterAdminEmails/);
  assert.match(script, /"TENANT_MASTER_ADMIN_EMAILS=\$MasterAdminEmails"/);
  assert.match(script, /\[Parameter\(Mandatory = \$true\)\]\s*\r?\n\s*\[string\]\$MasterAdminEmails/);
});

test("switches the bootstrap placeholder to the application image on port 3000", () => {
  assert.match(script, /"ingress",\s*"update"[\s\S]*?"--target-port",\s*"3000"/);
  assert.match(script, /ghcr\.io\/holgerimbery\/lab-tenant-manager:latest/);
  assert.match(script, /"containerapp",\s*"update"[\s\S]*?"--image",\s*\$Image/);
});

test("adds all four redirect URIs for the discovered FQDN", () => {
  for (const uri of [
    "callback/microsoft-entra-id",
    "onboard-callback",
    "adminconsent-callback",
    "callback/tenant-maker",
  ]) {
    assert.ok(
      script.includes(`https://$Fqdn/api/auth/${uri}`),
      `missing redirect URI https://$Fqdn/api/auth/${uri}`,
    );
  }
});

test("fails hard on a non-zero az exit code instead of pretending success", () => {
  assert.match(script, /if \(\$LASTEXITCODE -ne 0\) \{[\s\S]*?exit 1/);
  assert.match(script, /function Invoke-Az/);
});

test("never prints the client secret or the Cosmos key", () => {
  const lines = script.split(/\r?\n/);
  const offenders = lines.filter((line) => {
    const printing = /Write-Host|Write-Output|Out-File|Set-Content|Add-Content/.test(line);
    const sensitive = /\$cosmosKey\b|\$clientSecretPlain\b|\$nextAuthSecret\b|\$authSecret\b/.test(line);
    return printing && sensitive;
  });
  assert.deepEqual(offenders, [], `sensitive values must never be printed or written: ${offenders.join(" | ")}`);
  assert.doesNotMatch(script, /Set-Content|Out-File/, "the script must not write any file");
});

test("prompts for the client secret securely when it is not supplied", () => {
  assert.match(script, /\[securestring\]\$ClientSecret/);
  assert.match(script, /Read-Host[^\r\n]*-AsSecureString/);
});
