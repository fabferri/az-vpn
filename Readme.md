<properties
   pageTitle="Examples of Azure VPN"
   description="Examples of Azure VPN, ARM templates, scripts"
   services="Azure VPN"
   documentationCenter="na"
   authors="fabferri"
   manager=""
   editor=""/>

<tags
   ms.service="Configuration-Example-Azure"
   ms.devlang="na"
   ms.topic="article"
   ms.tgt_pltfrm="Azure"
   ms.workload="na"
   ms.date="29/06/2026"
   ms.author="fabferri" />

# Azure VPN examples

- Azure S2S VPN - VNG to VNG
  - [ARM template to create Site-to-Site VPN between two VPN Gateways](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-active-active-bgp-arm-template) [date: 11-08-2021]
  - [Site-to-Site VPN between two Azure VPN Gateways in active-active mode with BGP routing deployed by powershell](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-active-active-bgp-powershell) [date: 15-01-2025]
  - [Site-to-Site VPN between two Azure VPN Gateways deployed through Terraform](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-active-active-bgp-terraform) [date: 09-01-2025]
  - [Site-to-site VPN between two VPN Gateways deployed through Azure Python SDK](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-active-active-static-routing-python) [date: 08-09-2025]
  - [Site-to-Site VPN between two Azure VPN Gateways with static routing deployed through Terraform](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-active-active-static-routing-terraform) [date: 09-01-2025]
  - [Azure ARM templates to create site-to-site VPN between VNets](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-arm-template) [date: 18-01-2020]
  - [Azure ARM templates to create site-to-site VPN with digital certificate authentication](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-digitalcert-arm-template) [date: 30-06-2025]
  - [Azure Site-to-Site VPN with Digital Certificate Authentication in Az CLI](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-digitalcert-az-cli) [date: 29-01-2026]
  - [Azure Site-to-Site VPN with Digital Certificate Authentication by powershell](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-digitalcert-powershell) [date: 22-01-2026]
  - [Extending the GatewaySubnet address with VPN Gateway configured with site-to-site IPsec tunnels](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-extending-gatewaysubnet-az-cli) [date: 22-08-2025]
  - [Azure ARM templates to create site-to-site VPN by FQDN](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-fqdn-arm-template) [date: 28-01-2021]
  - [Azure IPv6 Site-to-Site VPN Deployment by ARM template](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-ipv6-inner-traffic-am-template) [date: 22-01-2026]
  - [Azure Site-to-Site VPN with IPv4/IPv6 Dual-Stack using AZ CLI](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-ipv6-inner-traffic-azcli) [date: 23-01-2026]
  - [Azure Site-to-Site VPN with IPv4/IPv6 Dual-Stack using powershell](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-ipv6-inner-traffic-powershell) [date: 23-01-2026]
  - [Connection between two VNets through site-to-site VPN with NAT](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-NAT) [date: 30-08-2021]
  - [Site-to-site VPN between Azure VNets with overlapping of address space and remote networks statically configured](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-NAT-static-localnetworks) [date: 30-05-2022]
  - [Site-to-Site VPN between Azure VPN Gateways with transit through ExpressRoute private peering](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-private-ip-transit-er) [date: 22-11-2023]
  - [Site-to-Site VPN connection over vnet peering using VPN Gateway private IP addresses](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-private-ip-transit-vnetpeering) [date: 21-11-2024]
  - [Site-to-site VPN between Azure VNets with remote networks statically configured](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-static-localnetworks) [date: 26-05-2022]
  - [Peered subnets deployed via Azure CLI and site-to-site IPsec tunnel between Azure VPN Gateways](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-subnetpeering-az-cli) [date: 28-11-2024]
  - [Site-to-site VPN between Azure VNets with remote networks statically configured and traffic selector](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-vng-traffic-selector) [date: 26-05-2022]
  - [Multiple VNet-to-VNet connections with VPN Gateways in a Partial Mesh configuration](https://github.com/fabferri/az-vpn/tree/main/vpn-vnet-2-vnet) [date: 25-11-2025]
  - [Summarization of address prefixes advertised over Site-to-Site VPN](https://github.com/fabferri/az-vpn/tree/main/summarization-prefixes-s2s-vng-vng-active-active-bgp) [date: 23-06-2026]

- Azure S2S VPN - VNG to NVA
  - [Single Site-to-Site IPsec tunnel between Azure VPN Gateway and Juniper vSRX](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-srx-1-tunnel-arm-template) [date: 26-11-2024]
  - [Two Site-to-Site IPsec tunnels between Azure VPN Gateway and Juniper vSRX](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-srx-2-tunnels-arm-template) [date: 28-11-2024]
  - [Site-to-Site IPsec tunnels between Azure VPN Gateway and Cisco Catalyst 8000v](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-catalyst-ipv4-arm-template) [date: 02-07-2025]
  - [Site-to-Site IPsec tunnels in dual stack with IPv4 and IPv6 between Azure VPN Gateway and Cisco Catalyst](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-catalyst-ipv6-inner-traffic) [date: 23-07-2025]
  - [Site-to-Site VPN between strongSwan and Azure VPN Gateway with Custom IPsec/IKE Policy (GCMAES256)](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-strongswan-1nic-custom-policy) [date: 20-06-2026]
  - [Site-to-Site VPN between strongSwan with two NICs and Azure VPN Gateway with Custom IPsec/IKE Policy (GCMAES256)](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-strongswan-2nic-custom-policy) [date: 22-06-2026]
  - [Building Azure-to-StrongSwan Site-to-Site VPN with X.509 Digital Certificates](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-strongswan-digitalcert-custom-policy) [date: 29-06-2026]
  - [Using Windows Server 2019 as NVA for site-to-site VPN](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-winvm) [date: 12-03-2021]

- Azure S2S VPN - Routing
  - [Azure VPN Gateway Routing and Connection by Azure library for Python](https://github.com/fabferri/az-vpn/tree/main/s2s-vng-routing-table-python) [date: 08-09-2025]

- Azure P2S VPN
  - [Workshop: Point-to-Site VPN configuration](https://github.com/fabferri/az-vpn/tree/main/p2s-arm-template) [date: 15-04-2024]
  - [Multipool address for P2S connection in Azure VPN Gateway by ARM template](https://github.com/fabferri/az-vpn/tree/main/p2s-vng-multipool-address-arm-template) [date: 03-04-2025]
  - [Multipool address for P2S connection in Azure VPN Gateway by powershell](https://github.com/fabferri/az-vpn/tree/main/p2s-vng-multipool-address-powershell) [date: 18-03-2025]

- Azure DNS Private Resolver
  - [Configuration with Azure DNS private resolver](https://github.com/fabferri/az-vpn/tree/main/dns-private-resolver-arm-template) [date: 16-06-2023]

- VPN Customer Controlled Maintenance
  - [VPN Customer Controlled Maintenance](https://github.com/fabferri/az-vpn/tree/main/vpn-customer-controlled%20maintenance) [date: 11-02-2026]
