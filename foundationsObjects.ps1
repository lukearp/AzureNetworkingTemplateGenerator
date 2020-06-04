$jsonMaster = @"
{
  "`$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {},  
  "resources": []
}
"@
$jsonNested = @'
		{{
			"apiVersion": "2017-05-10",
			"name": "[concat('{0}',resourceGroup().location)]",
			"type": "Microsoft.Resources/deployments",
			"resourceGroup": "{1}",
			"subscriptionId": "{2}",
			"properties": {{
				"mode": "Incremental",
				"template": {{
					"$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
					"contentVersion": "1.0.0.0",
					"resources": []
				}}
			}},
            "dependsOn": []
		}}
'@
$jsonVnet = @'
        {{
			"name": "[{0}]",
			"type": "Microsoft.Network/virtualNetworks",
			"apiVersion": "2017-10-01",
			"location": "[resourceGroup().location]",
			"tags": {{}},
			"properties": {{
				"addressSpace": {{
					"addressPrefixes": {1}
				}},
				"dhcpOptions": {{
					"dnsServers": []
				}},
				"subnets": []
			}},
            "dependsOn": []			
		}}
'@
$jsonVnetRef = @'
        {{
			"name": "[concat('{0}',resourceGroup().location)]",
			"type": "Microsoft.Network/virtualNetworks",
			"apiVersion": "2017-10-01",
			"location": "[resourceGroup().location]",
			"tags": {{}},
			"properties": "[reference('{1}','2017-10-01','Full').properties]",
            "dependsOn": []			
		}}
'@
$jsonSubnet = @'
        {{
			"name": "{0}",
			"properties": {{
				"addressPrefix": "{1}",
                "networkSecurityGroup": {{
                    "id": "{2}"
                }}
			}}
		}}
'@

$jsonSubnetGateway = @'
        {{
			"name": "{0}",
			"properties": {{
				"addressPrefix": "{1}"
			}}
		}}
'@

$jsonNewtorkSecurityGroup = @'
{{
	"name": "{0}",
	"type": "Microsoft.Network/networkSecurityGroups",
	"apiVersion": "2017-10-01",
	"location": "[resourceGroup().location]",
	"tags": {{}},
	"properties": {{
		"securityRules": []
	}}
}}
'@

$jsonNetworkSecurityRulesDMZ = @"
[{
    "name": "No-Outbound-VNET",
    "properties": {
	"description": "Doesn't Allow public facing servers to communicate with internal resources",
	"protocol": "*",
    "sourceAddressPrefix": "VirtualNetwork",
    "destinationAddressPrefix": "VirtualNetwork",
    "sourcePortRange": "*",
    "destinationPortRange": "*",
	"access": "Deny",
	"priority": 4000,
	"direction": "outbound"
    }
},
{
    "name": "Allow-DNS",
    "properties": {
	"description": "Allows DMZ Servers to hit nameservers",
	"protocol": "*",
    "sourceAddressPrefix": "VirtualNetwork",
    "destinationAddressPrefix": "*",
    "sourcePortRange": "*",
    "destinationPortRange": "53",
	"access": "Allow",
	"priority": 3999,
	"direction": "outbound"
    }
}]
"@

$jsonNetworkSecurityRulesDefault = @'
{{
    "name": "[concat('{0}',resourceGroup().location)]",
    "properties": {{
	"description": "{1}",
	"protocol": "{2}",
    "sourceAddressPrefix": "{3}",
	"sourceAddressPrefixes": {4},
    "destinationAddressPrefix": "{5}",
	"destinationAddressPrefixes": {6},
    "sourcePortRange": "{7}",
	"sourcePortRanges": {8},
    "destinationPortRange": "{9}",
	"destinationPortRanges": {10},
	"access": "{11}",
	"priority": {12},
	"direction": "{13}"
    }}
}}
'@

$jsonPubIp = @'
		{{
			"apiVersion": "2015-05-01-preview",
			"type": "Microsoft.Network/publicIPAddresses",
			"name": "{0}",
			"location": "[resourceGroup().location]",
			"properties": {{
				"publicIPAllocationMethod": "Dynamic"
			}}
		}}
'@
$jsonHubPeering = @'
{{
	"name": "{0}",
	"type": "Microsoft.Network/virtualNetworks/virtualNetworkPeerings",
	"apiVersion": "2017-10-01",
	"properties": {{
		"allowVirtualNetworkAccess": true,
		"allowForwardedTraffic": true,
		"allowGatewayTransit": true,
		"useRemoteGateways": false,
		"remoteVirtualNetwork": {{
			"id": "{1}"
		}}
	}},
    "dependsOn": []
}}
'@
$jsonSpokePeering = @'
{{
	"name": "{0}",
	"type": "Microsoft.Network/virtualNetworks/virtualNetworkPeerings",
	"apiVersion": "2017-10-01",
	"properties": {{
		"allowVirtualNetworkAccess": true,
		"allowForwardedTraffic": true,
		"allowGatewayTransit": false,
		"useRemoteGateways": true,
		"remoteVirtualNetwork": {{
			"id": "{1}"
		}}
	}},
    "dependsOn": []
}}
'@
$jsonGatewayVPN = @'
{{
	"name": "[concat(resourceGroup().location,'-gw')]",
	"type": "Microsoft.Network/virtualNetworkGateways",
	"apiVersion": "2017-10-01",
	"location": "[resourceGroup().location]",
	"tags": {{}},
	"properties": {{
		"ipConfigurations": [{{
			"properties": {{
				"subnet": {{
					"id": "[resourceId({1})]"
				}},
				"publicIPAddress": {{
					"id": "[resourceId({2})]"
				}}
			}},
			"name": "ipConfig1"
		}}],
		"gatewayType": "{3}",
		"vpnType": "{4}",
		"enableBgp": true,
		"activeActive": false,
		"sku": {{
			"name": "{5}",
			"tier": "{6}"
		}},
		"bgpSettings": {{
			"asn": "{7}"
		}}
	}},
    "dependsOn": []
}}
'@
$jsonGatewayExpressRoute = @'
{{
	"name": "[concat(resourceGroup().location,'-er')]",
	"type": "Microsoft.Network/virtualNetworkGateways",
	"apiVersion": "2017-10-01",
	"location": "[resourceGroup().location]",
	"tags": {{}},
	"properties": {{
		"ipConfigurations": [{{
			"properties": {{
				"subnet": {{
					"id": "[resourceId({1})]"
				}},
				"publicIPAddress": {{
					"id": "[resourceId({2})]"
				}}
			}},
			"name": "ipConfig1"
		}}],
		"gatewayType": "{3}",
		"activeActive": false,
		"sku": {{
			"name": "{4}",
			"tier": "{5}"
		}}
	}},
    "dependsOn": []
}}
'@
$jsonGatewayVPNRef = @'
{{
	"name": "{0}",
	"type": "Microsoft.Network/virtualNetworkGateways",
	"apiVersion": "2017-10-01",
	"location": "[resourceGroup().location]",
	"tags": {{}},
	"properties": "[reference('{1}','2017-10-01','Full').properties]",
    "dependsOn": []
}}
'@
$jsonVnetToVnetCon = @'
{{
	"name": "{0}",
	"type": "Microsoft.Network/connections",
	"apiVersion": "2017-10-01",
	"location": "[resourceGroup().location]",
	"tags": {{}},
	"properties": {{
		"virtualNetworkGateway1": {{
			"id": "{1}"
		}},
		"virtualNetworkGateway2": {{
			"id": "{2}"			
		}},
		"connectionType": "Vnet2Vnet",
		"sharedKey": "{3}",
		"enableBgp": true
	}},
    "dependsOn": []
}}
'@

$jsonRecoveryVault = @'
{{
	"name": "{0}",
	"type": "Microsoft.RecoveryServices/vaults",
	"apiVersion": "2016-06-01",
	"location": "[resourceGroup().location]",
	"tags": {{}},
	"properties": {{}},
	"sku": {{
		"name": "Standard"
	}}
}}
'@

$jsonParameters = @'
{
  "`$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {}
}
'@
