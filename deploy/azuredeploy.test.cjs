const { test } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");

const template = JSON.parse(readFileSync(join(__dirname, "azuredeploy.json"), "utf8"));
const regions = {
  "north-america": "unitedstates",
  "the-americas": "unitedstates",
  "eu-efta": "europe",
  "europe-uk": "europe",
  emea: "europe",
  "asia-pacific": "australia",
};

test("geography is an explicit required choice, separate from Azure hosting", () => {
  const parameter = template.parameters.powerPlatformGeography;
  assert.equal(parameter.type, "string");
  assert.equal(Object.hasOwn(parameter, "defaultValue"), false);
  assert.deepEqual(parameter.allowedValues, Object.keys(regions));
  assert.equal(template.parameters.location.defaultValue, "[resourceGroup().location]");
  assert.deepEqual(template.variables.powerPlatformRegions, regions);
});

test("both region settings flow through the nested deployment without changing worker behavior", () => {
  const deployment = template.resources.find((resource) => resource.name === "containerapp");
  const inputs = deployment.properties.parameters;
  assert.equal(inputs.powerPlatformRegion.value,
    "[variables('powerPlatformRegions')[parameters('powerPlatformGeography')]]");
  assert.equal(inputs.powerPlatformMacroRegion.value, "[parameters('powerPlatformGeography')]");

  const nested = deployment.properties.template;
  assert.equal(nested.parameters.powerPlatformRegion.type, "string");
  assert.equal(nested.parameters.powerPlatformMacroRegion.type, "string");
  const app = nested.resources.find((resource) => resource.type === "Microsoft.App/containerApps");
  const env = app.properties.template.containers[0].env;
  assert.equal(new Set(env.map((item) => item.name)).size, env.length);
  assert.equal(env.find((item) => item.name === "PP_DEFAULT_REGION").value, "[parameters('powerPlatformRegion')]");
  assert.equal(env.find((item) => item.name === "PP_PAC_MACRO_REGION").value, "[parameters('powerPlatformMacroRegion')]");
  assert.equal(env.find((item) => item.name === "DEVELOPMENT_WORKER_ENABLED").value, "true");
  assert.equal(app.properties.template.scale.minReplicas, 1);

  for (const [geography, region] of Object.entries(regions)) {
    const parameters = {
      powerPlatformRegion: template.variables.powerPlatformRegions[geography],
      powerPlatformMacroRegion: geography,
    };
    const resolved = Object.fromEntries(env.filter((item) => item.name.startsWith("PP_")).map((item) => {
      const match = item.value.match(/^\[parameters\('([^']+)'\)\]$/);
      assert.ok(match, `Unexpected expression for ${item.name}`);
      return [item.name, parameters[match[1]]];
    }));
    assert.deepEqual(resolved, { PP_DEFAULT_REGION: region, PP_PAC_MACRO_REGION: geography });
  }
});

test("keyvault does not attempt to set enablePurgeProtection to false", () => {
  const kvDeployment = template.resources.find((resource) => resource.name === "keyvault");
  const nested = kvDeployment.properties.template;
  const kvResource = nested.resources.find((resource) => resource.type === "Microsoft.KeyVault/vaults");
  assert.equal(Object.hasOwn(kvResource.properties, "enablePurgeProtection"), false,
    "enablePurgeProtection must not be explicitly set to false because Azure policies or existing vaults reject disabling it");
});

