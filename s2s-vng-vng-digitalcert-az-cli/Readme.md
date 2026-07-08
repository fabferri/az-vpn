<properties
   pageTitle="Site-to-Site VPN between two Azure VPN Gateways with digital certificates authentication in AZ CLI"
   description="Site-to-Site VPN between two Azure VPN Gateway with digital certificate authetication deployed through AZ CLI"
   services="Site-to-Site VPN"
   documentationCenter="na"
   authors="fabferri"
   editor="fabferri"/>

<tags
   ms.service="Configuration-Example-Azure"
   ms.devlang="na"
   ms.topic="article"
   ms.tgt_pltfrm="Azure"
   ms.workload="VPN Gateway"
   ms.date="20/06/2026"
   ms.author="fabferri" />

# Site-to-Site VPN between two Azure VPN Gateways with digital certificates authentication in AZ CLI

This project creates a Site-to-Site (S2S) VPN connection between two Azure Virtual Networks (VNets) using Azure VPN Gateways configured in active-active mode with digital certificate-based authentication.

The VPN tunnels are secured using X.509 certificates instead of pre-shared keys, providing stronger security for the VPN connection.

---

## Project Structure

```text
├── 01_vpn1.sh           - Creates the first VPN Gateway and VNet
├── 02_vpn2.sh           - Creates the second VPN Gateway and VNet
├── 03_vpn-conn.sh       - Establishes the S2S VPN connection between the two VNets
├── 04_vms.sh            - Deploys Virtual Machines in the VNets for testing
├── s2s-gen-certs.sh     - Generates the digital certificates for VPN authentication
├── init.json            - Configuration/initialization parameters
└── certs/               - Folder containing the generated certificates
    ├── cert-pwd.txt     - Password to access the .pfx files
    ├── s2s-cert1.cer    - Leaf certificate for VPN Gateway 1 (PEM format, public key only)
    ├── s2s-cert1.csr    - Certificate Signing Request for leaf certificate 1
    ├── s2s-cert1.key    - Private key for leaf certificate 1
    ├── s2s-cert1.pfx    - PKCS#12 leaf certificate bundle for VPN Gateway 1 (contains private key + chain) [used by 01_vpn1.sh]
    ├── s2s-cert2.cer    - Leaf certificate for VPN Gateway 2 (PEM format, public key only)
    ├── s2s-cert2.csr    - Certificate Signing Request for leaf certificate 2
    ├── s2s-cert2.key    - Private key for leaf certificate 2
    ├── s2s-cert2.pfx    - PKCS#12 leaf certificate bundle for VPN Gateway 2 (contains private key + chain) [used by 02_vpn2.sh]
    ├── VPNRootCA1.cer   - Self-signed Root CA certificate for VPN Gateway 1 (PEM format) [used by 03_vpn-conn.sh]
    ├── VPNRootCA1.cert  - Self-signed Root CA certificate for VPN Gateway 1 (DER binary format)
    ├── VPNRootCA1.key   - Private key for Root CA 1
    ├── VPNRootCA1.srl   - Serial number file for Root CA 1
    ├── VPNRootCA2.cer   - Self-signed Root CA certificate for VPN Gateway 2 (PEM format) [used by 03_vpn-conn.sh]
    ├── VPNRootCA2.cert  - Self-signed Root CA certificate for VPN Gateway 2 (DER binary format)
    ├── VPNRootCA2.key   - Private key for Root CA 2
    └── VPNRootCA2.srl   - Serial number file for Root CA 2
```


---

## Architecture Overview

This project uses digital certificate authentication for the S2S VPN tunnels. The digital certificates are securely stored in Azure Key Vault, and each VPN Gateway accesses its certificates through a User-Assigned Managed Identity.

[![1]][1]

For Key Vault access control, this project implements Role-Based Access Control (RBAC) rather than the legacy Access Policy model. Microsoft has officially referred to Access Policies as "legacy since 2022" and recommends that all customers migrate to RBAC for improved security and governance.


Site-to-site certificate authentication relies on both **inbound** and **outbound** certificates to establish secure VPN tunnels between two Azure VPN Gateways.

### Certificate Types and Their Purpose

| Certificate Type                | Purpose | Storage | Contains Private Key |
|---------------------------------|---------|---------|----------------------|
| **Root CA Certificate**         | Self-signed certificate used to sign leaf certificates. Establishes the trust chain. | Local (used for signing) | Yes |
| **Outbound Certificate (Leaf)** | Used to verify connections going **from Azure to the remote site**. Signed by the Root CA. | Azure Key Vault (.pfx) | Yes |
| **Inbound Certificate (Leaf)**  | Used when connecting **from the remote site to Azure**. The public key is configured in the VPN connection. | Connection configuration (.cer) | No (public key only) |

### How Certificate Authentication Works

1. **Root CA Certificates** (`VPNRootCA1`, `VPNRootCA2`) are self-signed certificates created using `openssl` with `CA:TRUE` and `keyCertSign` key usage. They act as the trust anchor.

2. **Leaf Certificates** (`s2s-cert1.pfx`, `s2s-cert2.pfx`) are generated and signed by the corresponding Root CA certificate. They include:
   - Server and client authentication extended key usage
   - Minimum 2048-bit key length
   - Private key (required for outbound authentication)

3. **Outbound Certificate Flow** (Azure to Remote):
   - The outbound certificate (.pfx with private key) is stored in Azure Key Vault
   - The VPN Gateway accesses this certificate via its User-Assigned Managed Identity
   - When establishing the tunnel, the gateway presents this certificate to authenticate itself to the remote peer

4. **Inbound Certificate Flow** (Remote to Azure):
   - The inbound certificate's public key (.cer) is configured in the VPN connection settings
   - The remote VPN device presents its certificate
   - Azure validates the certificate chain against the configured inbound certificate chain

### Project Certificate Mapping

Each VPN Gateway is configured with its own User-Assigned Managed Identity to securely access certificates stored in Azure Key Vault:

| VPN Gateway | User Managed Identity | Key Vault       | Outbound Certificate (Key Vault) | Inbound Certificate Chain |
|-------------|-----------------------|-----------------|----------------------------------|---------------------------|
| gw1         | gw1-s2s-kv            | kv-gw1-{suffix} | gw1-cert (from s2s-cert1.pfx)    | VPNRootCA2.cer            |
| gw2         | gw2-s2s-kv            | kv-gw2-{suffix} | gw2-cert (from s2s-cert2.pfx)    | VPNRootCA1.cer            |

Each gateway trusts the other gateway's root certificate:
- **Gateway1** uses the leaf certificate CN=s2s-cert1 (signed by VPNRootCA1) for its outbound certificate and trusts VPNRootCA2 for inbound connections.
- **Gateway2** uses the leaf certificate CN=s2s-cert2 (signed by VPNRootCA2) for its outbound certificate and trusts VPNRootCA1 for inbound connections.

[![2]][2]

The leaf certificates are imported in Key Vaults; the diagram shows how VPN Gateways access the leaf certificates stored in Key Vaults:

[![3]][3]

A network diagram with VPN connections is shown below:
[![4]][4]



---

### How the Scripts Orchestrate Key Vault Access

The scripts `01_vpn1.sh` and `02_vpn2.sh` follow the same pattern to configure secure access:

1. **Create User-Assigned Managed Identity**
   - Each VPN Gateway gets its own managed identity (e.g., `gw1-s2s-kv`, `gw2-s2s-kv`)
   - Created using `az identity create`

2. **Create Key Vault with RBAC**
   - A dedicated Key Vault is created for each gateway
   - Key Vault names are generated with a unique suffix based on subscription, resource group, and gateway name

3. **Assign RBAC Roles to Managed Identity**
   - **Key Vault Secrets User** (`4633458b-17de-408a-b874-0445c86b69e6`): Allows get/list secrets
   - **Key Vault Certificate User** (`db79e9a7-68ee-4b58-9aeb-b90e7c24fcba`): Allows get/list certificates

4. **Assign RBAC Role to Current User**
   - **Key Vault Certificates Officer** (`a4417e6f-fecd-4de8-b567-7b0420556985`): Grants full certificate management permissions to import certificates

5. **Import Certificate to Key Vault**
   - The PFX certificate is imported using `az keyvault certificate import`
   - Each gateway imports its respective certificate (`s2s-cert1.pfx` or `s2s-cert2.pfx`)

6. **Associate Managed Identity with VPN Gateway**
   - The VPN Gateway is configured with `az network vnet-gateway identity assign --user-assigned ...`
   - This allows the gateway to authenticate to Key Vault and retrieve its certificate

---

## Prerequisites

- Azure CLI logged in and authorized for:
  - Resource creation in target subscription
  - Role assignment in target scope
- `jq` installed
- `openssl` available for certificate generation script
- Bash shell (tested on macOS and Linux)

## Required `init.json` Fields

At minimum:

```json
{
  "subscriptionName": "<subscription-name-or-id>",
  "rgName": "<resource-group>",
  "adminUsername": "<vm-admin-user>",
  "adminPassword": "<vm-admin-password>"
}
```

---

## Execution Order

Before running the deployment scripts, generate the certificates using:

```bash
./s2s-gen-certs.sh
```



This script creates the self-signed root CA certificates and leaf certificates required for VPN authentication; the digital certificates are stored in the `./certs` folder.

[![5]][5]

After generation of the digital certificates, run the scripts in the following sequence:

1. **Step 1:** `./01_vpn1.sh` - Deploy first VNet and VPN Gateway
1. **Step 2:** `./02_vpn2.sh` - Deploy second VNet and VPN Gateway
1. **Step 3:** `./03_vpn-conn.sh` - Create the S2S VPN connection
1. **Step 4:** `./04_vms.sh` - Deploy test VMs in both VNets
1. **Step 5 (Optional):** `RUN_REMOTE_SCRIPT=true ./04_vms.sh` - Deploy VMs and install nginx remotely

> [!NOTE]
> VPN Gateway deployment can take 30-45 minutes. The scripts `01_vpn1.sh` and `02_vpn2.sh` can run in parallel because they are independent.
> However, `03_vpn-conn.sh` has dependencies on both scripts and can only be executed after the successful completion of both `01_vpn1.sh` and `02_vpn2.sh`.

---

## Script Behavior Notes

### `01_vpn1.sh` and `02_vpn2.sh`

- Use `--public-ip-addresses` for dual public IP gateway creation.
- Attach managed identity using:
  - `az network vnet-gateway identity assign --user-assigned ...`
- Verify managed identity assignment explicitly.
- Include RBAC role assignment verification with retry loop.
- Include configurable retry for identity assign operation when gateway is busy.

Environment options:

| Variable | Default | Description |
|----------|---------|-------------|
| `RBAC_PROPAGATION_MAX_ATTEMPTS` | `12` | Maximum retry attempts for RBAC propagation |
| `RBAC_PROPAGATION_SLEEP_SECONDS` | `5` | Sleep interval between RBAC retries |
| `RBAC_PROPAGATION_TIMEOUT_SECONDS` | — | Optional timeout (derives max attempts) |
| `GATEWAY_IDENTITY_ASSIGN_MAX_ATTEMPTS` | `20` | Maximum retry attempts for identity assignment |
| `GATEWAY_IDENTITY_ASSIGN_SLEEP_SECONDS` | `15` | Sleep interval between identity retries |

### `03_vpn-conn.sh`

- Ensures local network gateways exist and are aligned with gateway public IPs.
- Creates/enforces VPN certificate authentication per connection.
- Fails fast if authentication type is not `Certificate` after create/update.
- Prints connection summary including connection type and authentication type.

### `04_vms.sh`

- Deploys `vm1` in `vnet1/subnet1` and `vm2` in `vnet2/subnet1`.
- Ensures required subnets exist even if VNet already exists.
- Supports optional remote nginx installation via Run Command.

Environment option:

- `RUN_REMOTE_SCRIPT=true|false` — If unset, the script keeps the in-file default.

---

## Troubleshooting

### Gateway identity assignment fails with `AnotherOperationInProgress`

Use higher retries:

```bash
export GATEWAY_IDENTITY_ASSIGN_MAX_ATTEMPTS=40
export GATEWAY_IDENTITY_ASSIGN_SLEEP_SECONDS=20
./02_vpn2.sh
```

### VPN connection update reports transient operation errors

`03_vpn-conn.sh` already retries and validates actual resource state. Re-run safely.

### Remote nginx install appears skipped

- Confirm `RUN_REMOTE_SCRIPT=true` at execution time.
- Ensure script output includes:
  - `running remote nginx install script on VM ...`
  - `remote nginx install script completed on VM ...`

---

## References

- [Migration from Access Policy to RBAC](https://learn.microsoft.com/azure/key-vault/general/rbac-migration?tabs=cli)
- [Azure built-in roles for Key Vault data plane operations](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)

`Tag: Site-to-Site VPN, digital certificate authentication` <br>
`date: 08-07-2026`

<!--Image References-->

[1]: ./media/network-diagram.png "network diagram"
[2]: ./media/root-certificates.png "Root certificates"
[3]: ./media/outbound-certificates.png "VPN Gateway access to the leaf certificates stored in Key Vaults"
[4]: ./media/network-diagram-details.png "network diagram with details"
[5]: ./media/digital-certificates.png "Creation of digital certificates"


<!--Link References-->
