#!/bin/bash
# Script to create VPN Gateway with certificate authentication using managed identity and Key Vault
# The script creates a managed identity with readonly access to Key Vault integration to access the digital certificate required to establish a Connection
# $subscriptionName and $rgName collected by "init.json" file

vnet1Name='vnet1'
gw1Name='gw1'


gw1UserIdentityName='gw1-s2s-kv'
gw1ConfigName='gw1-config'
location='uksouth'

vnet1subnet1Name='subnet1'
vnetAddress='10.1.0.0/16'
gw1SubnetAddress='10.1.0.0/24'
vnet1subnet1Address='10.1.1.0/24'
gw1OutboundCertName='gw1-cert'

pathFiles="$(pwd)"
inputParams='init.json'
inputParamsFile="$pathFiles/$inputParams"

# Read parameters from JSON file
if [ ! -f "$inputParamsFile" ]; then
    echo "$(date) - error in reading the parameters file: $inputParamsFile"
    exit 1
fi

subscriptionName=$(jq -r '.subscriptionName' "$inputParamsFile")
rgName=$(jq -r '.rgName' "$inputParamsFile")

# Check the values of variables
echo "$(date) - values from file: $inputParams"
if [ -z "$subscriptionName" ] || [ "$subscriptionName" == "null" ]; then echo 'variable subscriptionName is null'; exit 1; else echo "   subscription name.....: $subscriptionName"; fi
if [ -z "$rgName" ] || [ "$rgName" == "null" ]; then echo 'variable rgName is null'; exit 1; else echo "   resource group name...: $rgName"; fi

# Generate unique Key Vault name
seed="$subscriptionName-$rgName-$gw1Name"
suffix=$(echo -n "$seed" | sha256sum | cut -c1-8)
keyVault1Name="kv-$gw1Name-$suffix"

# Set subscription
az account set --subscription "$subscriptionName"

# RBAC propagation retry settings (override via environment variables)
rbacPropagationMaxAttempts="${RBAC_PROPAGATION_MAX_ATTEMPTS:-12}"
rbacPropagationSleepSeconds="${RBAC_PROPAGATION_SLEEP_SECONDS:-5}"
rbacPropagationTimeoutSeconds="${RBAC_PROPAGATION_TIMEOUT_SECONDS:-}"

# If timeout is set, it takes precedence and derives max attempts from sleep interval.
if [ -n "$rbacPropagationTimeoutSeconds" ]; then
    if [ "$rbacPropagationSleepSeconds" -le 0 ] 2>/dev/null; then
        echo "$(date) - ERROR: RBAC_PROPAGATION_SLEEP_SECONDS must be > 0"
        exit 1
    fi
    rbacPropagationMaxAttempts=$(( (rbacPropagationTimeoutSeconds + rbacPropagationSleepSeconds - 1) / rbacPropagationSleepSeconds ))
fi

echo "$(date) - RBAC propagation settings: attempts=$rbacPropagationMaxAttempts sleep=${rbacPropagationSleepSeconds}s"

# VPN gateway identity assignment retry settings (override via environment variables)
gatewayIdentityAssignMaxAttempts="${GATEWAY_IDENTITY_ASSIGN_MAX_ATTEMPTS:-20}"
gatewayIdentityAssignSleepSeconds="${GATEWAY_IDENTITY_ASSIGN_SLEEP_SECONDS:-15}"

if [ "$gatewayIdentityAssignSleepSeconds" -le 0 ] 2>/dev/null; then
    echo "$(date) - ERROR: GATEWAY_IDENTITY_ASSIGN_SLEEP_SECONDS must be > 0"
    exit 1
fi

echo "$(date) - gateway identity assignment retry settings: attempts=$gatewayIdentityAssignMaxAttempts sleep=${gatewayIdentityAssignSleepSeconds}s"

# Wait for RBAC role assignment visibility in ARM graph (eventual consistency)
wait_for_role_assignment() {
    local assigneeObjectId="$1"
    local roleDefinitionId="$2"
    local scope="$3"
    local maxAttempts="$rbacPropagationMaxAttempts"
    local sleepSeconds="$rbacPropagationSleepSeconds"
    local attempt=1

    while [ $attempt -le $maxAttempts ]; do
        assignmentId=$(az role assignment list \
            --assignee-object-id "$assigneeObjectId" \
            --role "$roleDefinitionId" \
            --scope "$scope" \
            --query "[0].id" -o tsv 2>/dev/null)

        if [ -n "$assignmentId" ]; then
            return 0
        fi

        echo "$(date) - waiting for role assignment propagation (attempt $attempt/$maxAttempts)"
        sleep "$sleepSeconds"
        attempt=$((attempt + 1))
    done

    return 1
}

assign_gateway_identity_with_retry() {
    local resourceGroup="$1"
    local gatewayName="$2"
    local userAssignedIdentityId="$3"
    local attempt=1

    while [ $attempt -le "$gatewayIdentityAssignMaxAttempts" ]; do
        assignError=$(az network vnet-gateway identity assign \
            --resource-group "$resourceGroup" \
            --name "$gatewayName" \
            --user-assigned "$userAssignedIdentityId" \
            --output none 2>&1)

        if [ $? -eq 0 ]; then
            return 0
        fi

        if echo "$assignError" | grep -q "AnotherOperationInProgress"; then
            echo "$(date) - gateway operation in progress, retrying identity assignment (attempt $attempt/$gatewayIdentityAssignMaxAttempts)"
            sleep "$gatewayIdentityAssignSleepSeconds"
            attempt=$((attempt + 1))
            continue
        fi

        echo "$assignError"
        return 1
    done

    return 1
}

# Create Resource Group
echo "$(date) - Creating Resource Group"
if az group show --name "$rgName" &>/dev/null; then
    echo "Resource exists, skipping"
else
    az group create --name "$rgName" --location "$location"
fi

# Add Tag Values to the Resource Group
az group update --name "$rgName" --tags usage="s2s-digitalcertificates" --output none

# Create Virtual Network
echo "$(date) - Creating Virtual Network"
if az network vnet show --resource-group "$rgName" --name "$vnet1Name" &>/dev/null; then
    echo "  resource exists, skipping"
else
    az network vnet create \
        --resource-group "$rgName" \
        --name "$vnet1Name" \
        --address-prefix "$vnetAddress" \
        --location "$location"
    
    # Add Subnets
    echo "$(date) - Adding subnets"
    az network vnet subnet create \
        --resource-group "$rgName" \
        --vnet-name "$vnet1Name" \
        --name "$vnet1subnet1Name" \
        --address-prefix "$vnet1subnet1Address"
    
    az network vnet subnet create \
        --resource-group "$rgName" \
        --vnet-name "$vnet1Name" \
        --name "GatewaySubnet" \
        --address-prefix "$gw1SubnetAddress"
fi

# Create or get managed identity
echo "$(date) - Getting managed identity: $gw1UserIdentityName"
if ! az identity show --resource-group "$rgName" --name "$gw1UserIdentityName" &>/dev/null; then
    echo "$(date) - Creating managed identity: $gw1UserIdentityName"
    az identity create --resource-group "$rgName" --name "$gw1UserIdentityName" --location "$location"
    echo "$(date) - Created managed identity: $gw1UserIdentityName"
fi

gw1UserIdentityId=$(az identity show --resource-group "$rgName" --name "$gw1UserIdentityName" --query id -o tsv)
gw1UserIdentityPrincipalId=$(az identity show --resource-group "$rgName" --name "$gw1UserIdentityName" --query principalId -o tsv)

# Create Key Vault with RBAC enabled
echo "$(date) - Creating Key Vault: $keyVault1Name"
if ! az keyvault show --name "$keyVault1Name" --resource-group "$rgName" &>/dev/null; then
    deletedVaultExists=$(az keyvault list-deleted --query "[?name=='$keyVault1Name'] | length(@)" -o tsv 2>/dev/null)
    if [ "$deletedVaultExists" = "1" ]; then
        echo "$(date) - clearing soft-deleted Key Vault with the same name: $keyVault1Name"
        az keyvault purge --name "$keyVault1Name" 2>/dev/null || true
    fi
    echo "$(date) - creating new Key Vault with RBAC enabled"
    az keyvault create --name "$keyVault1Name" --resource-group "$rgName" --location "$location"
else
    echo "$(date) - keyvault already exists, skipping creation: $keyVault1Name"
fi

keyVaultResourceId=$(az keyvault show --name "$keyVault1Name" --resource-group "$rgName" --query id -o tsv)
echo "$(date) - Key Vault ResourceId: $keyVaultResourceId"

# Grant managed identity access to Key Vault using RBAC
echo "$(date) - granting managed identity RBAC access to Key Vault: $keyVault1Name"

# Assign "Key Vault Secrets User" role (for get/list secrets)
secretsUserRoleId="4633458b-17de-408a-b874-0445c86b69e6"
existingSecretsAssignment=$(az role assignment list --assignee-object-id "$gw1UserIdentityPrincipalId" --role "$secretsUserRoleId" --scope "$keyVaultResourceId" --query "[0].id" -o tsv)
if [ -z "$existingSecretsAssignment" ]; then
    echo "$(date) - creating role assignment: Key Vault Secrets User"
    az role assignment create --assignee-object-id "$gw1UserIdentityPrincipalId" --assignee-principal-type ServicePrincipal \
        --role "$secretsUserRoleId" --scope "$keyVaultResourceId" --output none
fi

if wait_for_role_assignment "$gw1UserIdentityPrincipalId" "$secretsUserRoleId" "$keyVaultResourceId"; then
    echo "$(date) - verified role assignment: Key Vault Secrets User"
else
    echo "$(date) - ERROR: role assignment not visible after wait: Key Vault Secrets User"
    exit 1
fi

# Assign "Key Vault Certificate User" role (for get/list certificates)
certUserRoleId="db79e9a7-68ee-4b58-9aeb-b90e7c24fcba"
existingCertUserAssignment=$(az role assignment list --assignee-object-id "$gw1UserIdentityPrincipalId" --role "$certUserRoleId" --scope "$keyVaultResourceId" --query "[0].id" -o tsv)
if [ -z "$existingCertUserAssignment" ]; then
    echo "$(date) - creating role assignment: Key Vault Certificate User"
    az role assignment create --assignee-object-id "$gw1UserIdentityPrincipalId" --assignee-principal-type ServicePrincipal \
        --role "$certUserRoleId" --scope "$keyVaultResourceId" --output none
fi

if wait_for_role_assignment "$gw1UserIdentityPrincipalId" "$certUserRoleId" "$keyVaultResourceId"; then
    echo "$(date) - verified role assignment: Key Vault Certificate User"
else
    echo "$(date) - ERROR: role assignment not visible after wait: Key Vault Certificate User"
    exit 1
fi

echo "$(date) - RBAC role assignments created for managed identity"

currentUser=$(az account show --query user.name -o tsv)
echo "$(date) - getting user account ID: $currentUser"

# Get current user's Object ID for RBAC assignment
currentUserObjectId=$(az ad user show --id "$currentUser" --query id -o tsv)

# Assign "Key Vault Certificates Officer" role (for full certificate management)
certOfficerRoleId="a4417e6f-fecd-4de8-b567-7b0420556985"

# Check if role assignment exists
existingAssignment=$(az role assignment list --assignee "$currentUserObjectId" --role "$certOfficerRoleId" --scope "$keyVaultResourceId" --query "[0].id" -o tsv)

if [ -z "$existingAssignment" ]; then
    echo "$(date) - Creating Role assignment for current user to Key Vault Certificates Officer role"
    az role assignment create --assignee-object-id "$currentUserObjectId" --assignee-principal-type User \
        --role "$certOfficerRoleId" --scope "$keyVaultResourceId" --output none
    echo "$(date) - Role assignment created"
else
    echo "$(date) - Role assignment already exists, skipping"
fi

if wait_for_role_assignment "$currentUserObjectId" "$certOfficerRoleId" "$keyVaultResourceId"; then
    echo "$(date) - verified role assignment: Key Vault Certificates Officer"
else
    echo "$(date) - ERROR: role assignment not visible after wait: Key Vault Certificates Officer"
    exit 1
fi

echo "$(date) - RBAC role assignment created for user: $currentUser"

# Import certificate in keyvault
cert1FilePath="$pathFiles/certs/s2s-cert1.pfx"
if az keyvault certificate show --vault-name "$keyVault1Name" --name "$gw1OutboundCertName" &>/dev/null; then
    echo "$(date) - certificate already exists in keyvault, skipping: $gw1OutboundCertName"
else
    echo "$(date) - importing certificate in keyvault: $keyVault1Name"
    if [ -f "$cert1FilePath" ]; then
        az keyvault certificate import \
            --vault-name "$keyVault1Name" \
            --name "$gw1OutboundCertName" \
            --file "$cert1FilePath" \
            --password "12345"
        echo "$(date) - certificate imported successfully: $gw1OutboundCertName"
    else
        echo "$(date) - ERROR: certificate file not found: $cert1FilePath"
        echo "$(date) - Please run s2s-gen-certs.sh first to generate the certificates"
        exit 1
    fi
fi
# Create public IP1 for the VPN gateway
gw1pubIP1Name="${gw1Name}pip1"

# Create public IP for VPN Gateway
echo "$(date) - getting public ip exists: $gw1pubIP1Name"
if az network public-ip show --resource-group "$rgName" --name "$gw1pubIP1Name" &>/dev/null; then
    echo "$(date) - public ip exists, skipping: $gw1pubIP1Name"
else
    az network public-ip create \
        --resource-group "$rgName" \
        --name "$gw1pubIP1Name" \
        --location "$location" \
        --allocation-method Static \
        --sku Standard \
        --tier Regional \
        --zone 1 2 3
    echo "$(date) - public ip created: $gw1pubIP1Name"
fi

# Create public IP2 for the VPN gateway
gw1pubIP2Name="${gw1Name}pip2"
# Create public IP for VPN Gateway
echo "$(date) - getting public ip exists: $gw1pubIP2Name"
if az network public-ip show --resource-group "$rgName" --name "$gw1pubIP2Name" &>/dev/null; then
    echo "$(date) - public ip exists, skipping: $gw1pubIP2Name"
else
    az network public-ip create \
        --resource-group "$rgName" \
        --name "$gw1pubIP2Name" \
        --location "$location" \
        --allocation-method Static \
        --sku Standard \
        --tier Regional \
        --zone 1 2 3
    echo "$(date) - public ip created: $gw1pubIP2Name"
fi

# Create VirtualNetworkGateway with managed identity
echo "$(date) - checking if the vpn gateway exists: $gw1Name"
if az network vnet-gateway show --resource-group "$rgName" --name "$gw1Name" &>/dev/null; then
    echo "$(date) - vpn gateway exists, skipping: $gw1Name"
else
    echo "$(date) - creating vpn gateway: $gw1Name"
    az network vnet-gateway create \
        --resource-group "$rgName" \
        --name "$gw1Name" \
        --location "$location" \
        --public-ip-addresses "$gw1pubIP1Name" "$gw1pubIP2Name" \
        --vnet "$vnet1Name" \
        --gateway-type Vpn \
        --vpn-type RouteBased \
        --sku VpnGw2AZ \
        --vpn-gateway-generation Generation2

    az network vnet-gateway wait \
        --resource-group "$rgName" \
        --name "$gw1Name" \
        --created

    echo "$(date) - vpn gateway created: $gw1Name"
fi

# Update VPN gateway with managed identity
echo "$(date) - updating vpn gateway with managed identity"
if assign_gateway_identity_with_retry "$rgName" "$gw1Name" "$gw1UserIdentityId"; then
    az network vnet-gateway wait \
        --resource-group "$rgName" \
        --name "$gw1Name" \
        --updated

    identityAssigned=$(az network vnet-gateway show \
        --resource-group "$rgName" \
        --name "$gw1Name" \
        --query "contains(keys(identity.userAssignedIdentities), '$gw1UserIdentityId')" \
        -o tsv)

    if [ "$identityAssigned" = "true" ]; then
        echo "$(date) - managed identity assigned successfully: $gw1UserIdentityId"
    else
        echo "$(date) - ERROR: managed identity assignment not found on gateway"
        exit 1
    fi
else
    echo "$(date) - ERROR: failed to update vpn gateway identity"
    exit 1
fi

gw1ProvisioningState=$(az network vnet-gateway show --resource-group "$rgName" --name "$gw1Name" --query provisioningState -o tsv)
echo "$(date) - vpn gateway status: $gw1ProvisioningState"
echo "$(date) - vpn gateway with managed identity configured"
