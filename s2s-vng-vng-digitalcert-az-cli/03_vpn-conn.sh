#!/bin/bash
# Script to create VPN Gateway Connections with certificate authentication.
# This script establishes site-to-site VPN connections between two gateways (gw1 and gw2)
# using certificate-based authentication. It:
#   1. Retrieves gateway public IPs and verifies provisioning state
#   2. Ensures managed identities are attached to gateways for Key Vault certificate access
#   3. Verifies Key Vault certificate roles are assigned to identities
#   4. Creates or updates local network gateways for routing configuration
#   5. Fetches certificates from Key Vault and creates/updates VPN connections
# NOTE: Azure RBAC is eventually consistent. Role assignments verified in this script
#       may take additional time to propagate to Key Vault's data-plane enforcement.

# Address space for the virtual networks
vnet1Address='10.1.0.0/16'
vnet2Address='10.2.0.0/16'

# VPN parameters
gw1Name='gw1'
localNetgw11Name='localNetGw11'
localNetgw12Name='localNetGw12'
gw1Connection11Name='Connection11'
gw1Connection12Name='Connection12'
gw1pubIP1Name="${gw1Name}pip1"
gw1pubIP2Name="${gw1Name}pip2"

gw2Name='gw2'
localNetgw21Name='localNetGw21'
localNetgw22Name='localNetGw22'
gw2Connection21Name='Connection21'
gw2Connection22Name='Connection22'
gw2pubIP1Name="${gw2Name}pip1"
gw2pubIP2Name="${gw2Name}pip2"
gw1UserIdentityName='gw1-s2s-kv'
gw2UserIdentityName='gw2-s2s-kv'

# Key Vault and Certificate parameters
location='uksouth'
gw1OutboundCertName='gw1-cert'
gw2OutboundCertName='gw2-cert'

keyVault1Name='kv-gw1-fb1a02'
keyVault2Name='kv-gw2-14eb01'

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

# Generate unique Key Vault names
seed="$subscriptionName-$rgName-$gw1Name"
suffix=$(echo -n "$seed" | sha256sum | cut -c1-8)
keyVault1Name="kv-$gw1Name-$suffix"

seed="$subscriptionName-$rgName-$gw2Name"
suffix=$(echo -n "$seed" | sha256sum | cut -c1-8)
keyVault2Name="kv-$gw2Name-$suffix"

# Set subscription
az account set --subscription "$subscriptionName"

# Fetch VPN Gateway1 public IP1
echo "$(date) - fetch vpn gateway1 - public IP1: $gw1pubIP1Name"
gw1publicIP1=$(az network public-ip show --resource-group "$rgName" --name "$gw1pubIP1Name" --query ipAddress -o tsv)
if [ -z "$gw1publicIP1" ]; then
    echo "$(date) - vpn gateway1 - error to retrieve public IPs"
    exit 1
fi
echo "$(date) - Azure vpn Gateway1 public IP1 .: $gw1publicIP1"

# Fetch VPN Gateway1 public IP2
echo "$(date) - fetch vpn gateway1 - public IP2: $gw1pubIP2Name"
gw1publicIP2=$(az network public-ip show --resource-group "$rgName" --name "$gw1pubIP2Name" --query ipAddress -o tsv)
if [ -z "$gw1publicIP2" ]; then
    echo "$(date) - vpn gateway1 - error to retrieve public IPs"
    exit 1
fi
echo "$(date) - Azure vpn Gateway1 public IP2 .: $gw1publicIP2"



# Fetch VPN Gateway2 public IP1
echo "$(date) - fetch vpn gateway2 - public IP1: $gw2pubIP1Name"
gw2publicIP1=$(az network public-ip show --resource-group "$rgName" --name "$gw2pubIP1Name" --query ipAddress -o tsv)
if [ -z "$gw2publicIP1" ]; then
    echo "$(date) - vpn gateway2 - error to retrieve public IPs"
    exit 1
fi
echo "$(date) - Azure VPN Gateway2 public IP1 .: $gw2publicIP1"

# Fetch VPN Gateway2 public IP2
echo "$(date) - fetch vpn gateway2 - public IP2: $gw2pubIP2Name"
gw2publicIP2=$(az network public-ip show --resource-group "$rgName" --name "$gw2pubIP2Name" --query ipAddress -o tsv)
if [ -z "$gw2publicIP2" ]; then
    echo "$(date) - vpn gateway2 - error to retrieve public IPs"
    exit 1
fi
echo "$(date) - Azure VPN Gateway2 public IP2 .: $gw2publicIP2"



# Verify VPN Gateway1 deployment status
echo "$(date) - verifying VPN Gateway1 deployment status"
gw1State=$(az network vnet-gateway show --resource-group "$rgName" --name "$gw1Name" --query provisioningState -o tsv 2>/dev/null)
if [ -z "$gw1State" ]; then
    echo "$(date) - ERROR: VPN Gateway1 '$gw1Name' not found"
    exit 1
elif [ "$gw1State" != "Succeeded" ]; then
    echo "$(date) - ERROR: VPN Gateway1 '$gw1Name' is in state '$gw1State', not 'Succeeded'"
    echo "$(date) - Please wait for the gateway to finish provisioning before creating connections"
    exit 1
fi
echo "$(date) - VPN Gateway1 status: $gw1State"

# Verify VPN Gateway2 deployment status
echo "$(date) - verifying VPN Gateway2 deployment status"
ensure_gateway_identity() {
    local gatewayName="$1"
    local identityName="$2"

    local identityId
    identityId=$(az identity show --resource-group "$rgName" --name "$identityName" --query id -o tsv 2>/dev/null)
    if [ -z "$identityId" ]; then
        echo "$(date) - ERROR: managed identity not found: $identityName"
        exit 1
    fi

    local hasIdentity
    hasIdentity=$(az network vnet-gateway identity show \
        --resource-group "$rgName" \
        --name "$gatewayName" \
        --query "contains(keys(userAssignedIdentities), '$identityId')" \
        -o tsv 2>/dev/null)

    if [ "$hasIdentity" != "true" ]; then
        echo "$(date) - attaching managed identity '$identityName' to gateway '$gatewayName'"
        az network vnet-gateway identity assign \
            --resource-group "$rgName" \
            --name "$gatewayName" \
            --user-assigned "$identityId" >/dev/null || {
            echo "$(date) - ERROR: failed to attach managed identity '$identityName' to gateway '$gatewayName'"
            exit 1
        }
    else
        echo "$(date) - managed identity already attached to gateway '$gatewayName': $identityName"
    fi
}

# Ensure a managed identity has the required Key Vault Certificate User role on a vault.
# This function verifies that the specified managed identity has the 'Key Vault Certificate User'
# RBAC role assigned on the given Key Vault scope. If the role is not assigned, it creates the
# assignment. This role is required for VPN gateways to read certificates from Key Vault.
# NOTE: After role assignment, allow time for eventual consistency propagation before the
#       gateway attempts to access certificates from Key Vault.
ensure_keyvault_cert_role() {
    local identityName="$1"
    local vaultName="$2"

    local principalId
    principalId=$(az identity show --resource-group "$rgName" --name "$identityName" --query principalId -o tsv 2>/dev/null)
    if [ -z "$principalId" ]; then
        echo "$(date) - ERROR: failed to get principalId for identity: $identityName"
        exit 1
    fi

    local vaultId
    vaultId=$(az keyvault show --name "$vaultName" --query id -o tsv 2>/dev/null)
    if [ -z "$vaultId" ]; then
        echo "$(date) - ERROR: failed to get Key Vault id for: $vaultName"
        exit 1
    fi

    local certRoleCount
    certRoleCount=$(az role assignment list \
        --assignee-object-id "$principalId" \
        --scope "$vaultId" \
        --query "[?roleDefinitionName=='Key Vault Certificate User'] | length(@)" \
        -o tsv 2>/dev/null)

    if [ "$certRoleCount" = "0" ] || [ -z "$certRoleCount" ]; then
        echo "$(date) - assigning 'Key Vault Certificate User' on '$vaultName' to identity '$identityName'"
        az role assignment create \
            --assignee-object-id "$principalId" \
            --assignee-principal-type ServicePrincipal \
            --role "Key Vault Certificate User" \
            --scope "$vaultId" >/dev/null || {
            echo "$(date) - ERROR: failed assigning Key Vault role on '$vaultName' to '$identityName'"
            exit 1
        }
    else
        echo "$(date) - Key Vault certificate role already assigned: identity '$identityName' on '$vaultName'"
    fi
}

ensure_gateway_identity "$gw1Name" "$gw1UserIdentityName"
ensure_gateway_identity "$gw2Name" "$gw2UserIdentityName"

ensure_keyvault_cert_role "$gw1UserIdentityName" "$keyVault1Name"
ensure_keyvault_cert_role "$gw2UserIdentityName" "$keyVault2Name"

# Verify VPN Gateway2 deployment status
echo "$(date) - verifying VPN Gateway2 deployment status"
gw2State=$(az network vnet-gateway show --resource-group "$rgName" --name "$gw2Name" --query provisioningState -o tsv 2>/dev/null)
if [ -z "$gw2State" ]; then
    echo "$(date) - ERROR: VPN Gateway2 '$gw2Name' not found"
    exit 1
elif [ "$gw2State" != "Succeeded" ]; then
    echo "$(date) - ERROR: VPN Gateway2 '$gw2Name' is in state '$gw2State', not 'Succeeded'"
    echo "$(date) - Please wait for the gateway to finish provisioning before creating connections"
    exit 1
fi
echo "$(date) - VPN Gateway2 status: $gw2State"

# Ensure local network gateways match the desired remote gateway IP and address space.
# Local network gateways represent the remote VPN endpoints. This function creates the
# local gateway if it doesn't exist, or updates it if the remote IP address or address
# prefixes have changed. These gateways are used as targets for VPN connections.
ensure_local_gateway() {
    local name="$1"
    local prefixes="$2"
    local gatewayIp="$3"

    if az network local-gateway show --resource-group "$rgName" --name "$name" &>/dev/null; then
        currentIp=$(az network local-gateway show --resource-group "$rgName" --name "$name" --query gatewayIpAddress -o tsv)
        currentPrefix=$(az network local-gateway show --resource-group "$rgName" --name "$name" --query "localNetworkAddressSpace.addressPrefixes[0]" -o tsv)

        if [ "$currentIp" != "$gatewayIp" ] || [ "$currentPrefix" != "$prefixes" ]; then
            echo "$(date) - updating local network gateway: $name (ip: $currentIp -> $gatewayIp, prefix: $currentPrefix -> $prefixes)"
            az network local-gateway update \
                --resource-group "$rgName" \
                --name "$name" \
                --gateway-ip-address "$gatewayIp" \
                --local-address-prefixes "$prefixes" >/dev/null
        else
            echo "$(date) - local network gateway exists and is up to date: $name"
        fi
    else
        echo "$(date) - creating local network gateway: $name"
        az network local-gateway create \
            --resource-group "$rgName" \
            --name "$name" \
            --location "$location" \
            --local-address-prefixes "$prefixes" \
            --gateway-ip-address "$gatewayIp" >/dev/null
    fi
}

ensure_local_gateway "$localNetgw11Name" "$vnet1Address" "$gw1publicIP1"
ensure_local_gateway "$localNetgw12Name" "$vnet1Address" "$gw1publicIP2"
ensure_local_gateway "$localNetgw21Name" "$vnet2Address" "$gw2publicIP1"
ensure_local_gateway "$localNetgw22Name" "$vnet2Address" "$gw2publicIP2"

# Get certificate information from Key Vault
echo "$(date) - fetching certificate information from Key Vault"

# Check if certificates exist in Key Vault before fetching
if az keyvault certificate show --vault-name "$keyVault1Name" --name "$gw1OutboundCertName" &>/dev/null; then
    gw1OutboundCertUrl=$(az keyvault certificate show --vault-name "$keyVault1Name" --name "$gw1OutboundCertName" --query id -o tsv)
    gw1OutboundcertSubjectName=$(az keyvault certificate show --vault-name "$keyVault1Name" --name "$gw1OutboundCertName" --query "policy.x509CertificateProperties.subject" -o tsv | sed 's/^CN=//')
    echo "$(date) - Certificate $gw1OutboundCertName found in $keyVault1Name"
else
    echo "$(date) - WARNING: Certificate $gw1OutboundCertName not found in $keyVault1Name"
    echo "$(date) - Please run 01_vpn1.sh first to create the certificate"
    gw1OutboundCertUrl=""
    gw1OutboundcertSubjectName=""
fi

if az keyvault certificate show --vault-name "$keyVault2Name" --name "$gw2OutboundCertName" &>/dev/null; then
    gw2OutboundCertUrl=$(az keyvault certificate show --vault-name "$keyVault2Name" --name "$gw2OutboundCertName" --query id -o tsv)
    gw2OutboundcertSubjectName=$(az keyvault certificate show --vault-name "$keyVault2Name" --name "$gw2OutboundCertName" --query "policy.x509CertificateProperties.subject" -o tsv | sed 's/^CN=//')
    echo "$(date) - Certificate $gw2OutboundCertName found in $keyVault2Name"
else
    echo "$(date) - WARNING: Certificate $gw2OutboundCertName not found in $keyVault2Name"
    echo "$(date) - Please run 02_vpn2.sh first to create the certificate"
    gw2OutboundCertUrl=""
    gw2OutboundcertSubjectName=""
fi

# Read Inbound Certificate Chain files
echo "$(date) - reading inbound certificate chain files"
inboundCert1Path="$pathFiles/certs/VPNRootCA1.cer"
inboundCert2Path="$pathFiles/certs/VPNRootCA2.cer"

# Check if certificate files exist
if [ -f "$inboundCert1Path" ]; then
    # Remove PEM headers and get Base64 only
    inboundCert1Base64=$(cat "$inboundCert1Path" | grep -v "BEGIN CERTIFICATE" | grep -v "END CERTIFICATE" | tr -d '\n\r')
    echo "$(date) - inbound certificate chain1 loaded from $inboundCert1Path"
else
    echo "$(date) - WARNING: Certificate file not found: $inboundCert1Path"
    echo "$(date) - Please run s2s-gen-certs.sh first and copy certificates to certs/ folder"
    inboundCert1Base64=""
fi

if [ -f "$inboundCert2Path" ]; then
    # Remove PEM headers and get Base64 only
    inboundCert2Base64=$(cat "$inboundCert2Path" | grep -v "BEGIN CERTIFICATE" | grep -v "END CERTIFICATE" | tr -d '\n\r')
    echo "$(date) - inbound certificate chain2 loaded from $inboundCert2Path"
else
    echo "$(date) - WARNING: Certificate file not found: $inboundCert2Path"
    echo "$(date) - Please run s2s-gen-certs.sh first and copy certificates to certs/ folder"
    inboundCert2Base64=""
fi

# Display certificate authentication info
echo "$(date) - creating gw1 certificate authentication object"
echo "gw1 - OutboundcertURL..................: $gw1OutboundCertUrl"
echo "gw1 - Inbound certificate subjectName..: $gw2OutboundcertSubjectName"

echo "$(date) - creating gw2 certificate authentication object"
echo "gw2 - OutboundcertURL..................: $gw2OutboundCertUrl"
echo "gw2 - Inbound certificate subjectName..: $gw1OutboundcertSubjectName"

# Validate certificate availability before attempting to create connections
if [ -z "$gw1OutboundCertUrl" ] || [ -z "$gw2OutboundCertUrl" ] || [ -z "$inboundCert1Base64" ] || [ -z "$inboundCert2Base64" ]; then
    echo "$(date) - ERROR: One or more certificates are missing or invalid"
    echo "$(date) - Please ensure 01_vpn1.sh and 02_vpn2.sh have been run successfully"
    exit 1
fi

# Ensure a VPN connection exists and is configured with certificate-based authentication.
# This function creates a new VPN connection or updates an existing one to use certificate auth.
# It handles transient errors (GatewayBusy, AnotherOperationInProgress, RBAC lag) with retries,
# and waits for the authentication type to propagate from ARM to the API response (eventual consistency).
# On success, the connection's authenticationType is verified to be "Certificate" before returning.
# NOTE: Certificate auth configuration may lag in visibility; this function probes the connection
#       state after creation/update to ensure the auth type has propagated to the data-plane.
ensure_connection_cert_auth() {
    local connectionName="$1"
    local gatewayName="$2"
    local localGatewayName="$3"
    local outboundCertUrl="$4"
    local inboundCertBase64="$5"
    local inboundSubjectName="$6"
    local currentAuthType=""
    local authProbeAttempts=18
    local authProbeSleepSeconds=10

    certAuthJson="{\"outboundAuthCertificate\":\"$outboundCertUrl\",\"inboundAuthCertificateChain\":[\"$inboundCertBase64\"],\"inboundAuthCertificateSubjectName\":\"$inboundSubjectName\"}"

    if az network vpn-connection show --resource-group "$rgName" --name "$connectionName" &>/dev/null; then
        echo "$(date) - connection exists, enforcing certificate auth: $connectionName"
        currentAuthType=$(az network vpn-connection show --resource-group "$rgName" --name "$connectionName" --query authenticationType -o tsv 2>/dev/null)
    else
        echo "$(date) - creating vpn connection with certificate auth: $connectionName"
        local createOutput=""
        local createAttempt
        for createAttempt in 1 2 3 4 5; do
            createOutput=$(az network vpn-connection create \
                --resource-group "$rgName" \
                --name "$connectionName" \
                --location "$location" \
                --vnet-gateway1 "$gatewayName" \
                --local-gateway2 "$localGatewayName" \
                --auth-type Certificate \
                --cert-auth "$certAuthJson" \
                --routing-weight 3 2>&1)

            if [ $? -eq 0 ]; then
                break
            fi

            if echo "$createOutput" | grep -Eq "AnotherOperationInProgress|GatewayBusy|InternalServerError"; then
                echo "$(date) - transient create issue on '$connectionName' (attempt $createAttempt/5), retrying in 20s"
                sleep 20
                continue
            fi

            echo "$createOutput"
            echo "$(date) - ERROR: failed to create VPN connection: $connectionName"
            exit 1
        done

        if [ $createAttempt -eq 5 ] && [ -n "$createOutput" ] && ! az network vpn-connection show --resource-group "$rgName" --name "$connectionName" &>/dev/null; then
            echo "$createOutput"
            echo "$(date) - ERROR: failed to create VPN connection after retries: $connectionName"
            exit 1
        fi

        currentAuthType=""
        probeAttempt=1
        while [ $probeAttempt -le $authProbeAttempts ]; do
            currentAuthType=$(az network vpn-connection show \
                --resource-group "$rgName" \
                --name "$connectionName" \
                --query authenticationType -o tsv 2>/dev/null)

            if [ "$currentAuthType" = "Certificate" ]; then
                break
            fi

            echo "$(date) - waiting for certificate auth to be visible on '$connectionName' (attempt $probeAttempt/$authProbeAttempts)"
            sleep "$authProbeSleepSeconds"
            probeAttempt=$((probeAttempt + 1))
        done

        if [ "$currentAuthType" != "Certificate" ]; then
            echo "$(date) - ERROR: connection auth type is '$currentAuthType' after create, expected 'Certificate': $connectionName"
            exit 1
        fi
    fi

    if [ "$currentAuthType" = "Certificate" ]; then
        echo "$(date) - certificate auth already configured: $connectionName"
        return 0
    fi

    echo "$(date) - updating certificate auth on connection: $connectionName"
    local updateOutput=""
    local attempt
    for attempt in 1 2 3 4 5; do
        updateOutput=$(az network vpn-connection update \
            --resource-group "$rgName" \
            --name "$connectionName" \
            --auth-type Certificate \
            --cert-auth "$certAuthJson" 2>&1)

        if [ $? -eq 0 ]; then
            updatedAuthType=$(az network vpn-connection show \
                --resource-group "$rgName" \
                --name "$connectionName" \
                --query authenticationType -o tsv 2>/dev/null)

            if [ "$updatedAuthType" = "Certificate" ]; then
                echo "$(date) - certificate auth configured: $connectionName"
                return 0
            fi

            echo "$(date) - ERROR: connection auth type is '$updatedAuthType' after update, expected 'Certificate': $connectionName"
            exit 1
        fi

        if echo "$updateOutput" | grep -Eq "ForbiddenByRbac|Operation .* not found|InternalServerError|GatewayBusy|AnotherOperationInProgress"; then
            updatedAuthType=$(az network vpn-connection show \
                --resource-group "$rgName" \
                --name "$connectionName" \
                --query authenticationType -o tsv 2>/dev/null)

            if [ "$updatedAuthType" = "Certificate" ]; then
                echo "$(date) - certificate auth is already configured despite transient update error: $connectionName"
                return 0
            fi

            echo "$(date) - transient update issue on '$connectionName' (attempt $attempt/5), retrying in 20s"
            sleep 20
            continue
        fi

        echo "$updateOutput"
        echo "$(date) - ERROR: failed to configure certificate auth: $connectionName"
        exit 1
    done

    updatedAuthType=$(az network vpn-connection show \
        --resource-group "$rgName" \
        --name "$connectionName" \
        --query authenticationType -o tsv 2>/dev/null)

    if [ "$updatedAuthType" = "Certificate" ]; then
        echo "$(date) - certificate auth configured after retries: $connectionName"
        return 0
    fi

    echo "$updateOutput"
    echo "$(date) - ERROR: failed to configure certificate auth after retries: $connectionName"
    exit 1
}

# Configure all connections for certificate auth
ensure_connection_cert_auth "$gw1Connection11Name" "$gw1Name" "$localNetgw21Name" "$gw1OutboundCertUrl" "$inboundCert2Base64" "$gw2OutboundcertSubjectName"
ensure_connection_cert_auth "$gw1Connection12Name" "$gw1Name" "$localNetgw22Name" "$gw1OutboundCertUrl" "$inboundCert2Base64" "$gw2OutboundcertSubjectName"
ensure_connection_cert_auth "$gw2Connection21Name" "$gw2Name" "$localNetgw11Name" "$gw2OutboundCertUrl" "$inboundCert1Base64" "$gw1OutboundcertSubjectName"
ensure_connection_cert_auth "$gw2Connection22Name" "$gw2Name" "$localNetgw12Name" "$gw2OutboundCertUrl" "$inboundCert1Base64" "$gw1OutboundcertSubjectName"

# Verify connections
echo "$(date) - checking vpn connection: $gw1Connection11Name"
vpnConnection11=$(az network vpn-connection show --resource-group "$rgName" --name "$gw1Connection11Name" 2>/dev/null)
if [ -n "$vpnConnection11" ]; then
    echo "resource group............: $(echo "$vpnConnection11" | jq -r '.resourceGroup')"
    echo "gw1 - connection name.....: $(echo "$vpnConnection11" | jq -r '.name')"
    echo "gw1 - connection type.....: $(echo "$vpnConnection11" | jq -r '.connectionType')"
    echo "gw1 - authentication type.: $(echo "$vpnConnection11" | jq -r '.authenticationType')"
fi

echo '--------------------------------------------------------------------------'
# Verify connections
echo "$(date) - checking vpn connection: $gw1Connection12Name"
vpnConnection12=$(az network vpn-connection show --resource-group "$rgName" --name "$gw1Connection12Name" 2>/dev/null)
if [ -n "$vpnConnection12" ]; then
    echo "resource group............: $(echo "$vpnConnection12" | jq -r '.resourceGroup')"
    echo "gw1 - connection name.....: $(echo "$vpnConnection12" | jq -r '.name')"
    echo "gw1 - connection type.....: $(echo "$vpnConnection12" | jq -r '.connectionType')"
    echo "gw1 - authentication type.: $(echo "$vpnConnection12" | jq -r '.authenticationType')"
fi

echo '--------------------------------------------------------------------------'
echo "$(date) - checking vpn connection: $gw2Connection21Name"
vpnConnection21=$(az network vpn-connection show --resource-group "$rgName" --name "$gw2Connection21Name" 2>/dev/null)
if [ -n "$vpnConnection21" ]; then
    echo "resource group............: $(echo "$vpnConnection21" | jq -r '.resourceGroup')"
    echo "gw2 - connection name.....: $(echo "$vpnConnection21" | jq -r '.name')"
    echo "gw2 - connection type.....: $(echo "$vpnConnection21" | jq -r '.connectionType')"
    echo "gw2 - authentication type.: $(echo "$vpnConnection21" | jq -r '.authenticationType')"
fi

echo '--------------------------------------------------------------------------'
echo "$(date) - checking vpn connection: $gw2Connection22Name"
vpnConnection22=$(az network vpn-connection show --resource-group "$rgName" --name "$gw2Connection22Name" 2>/dev/null)
if [ -n "$vpnConnection22" ]; then
    echo "resource group............: $(echo "$vpnConnection22" | jq -r '.resourceGroup')"
    echo "gw2 - connection name.....: $(echo "$vpnConnection22" | jq -r '.name')"
    echo "gw2 - connection type.....: $(echo "$vpnConnection22" | jq -r '.connectionType')"
    echo "gw2 - authentication type.: $(echo "$vpnConnection22" | jq -r '.authenticationType')"
fi

echo '--------------------------------------------------------------------------'
# List connections and verify
connectionCount=$(az network vpn-connection list --resource-group "$rgName" --query "length(@)" -o tsv)
echo "$(date) - Total number of vpn Connections: $connectionCount"
