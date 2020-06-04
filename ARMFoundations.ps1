param(
    [string]$customerAbv,
    [ValidateSet("mac","mag")]
    [string]$cloud,
    [string]$deploymentAddressSpace,
    [string]$templateRootPath,
    [switch]$deployGateways,
    [ValidateSet("VPN","ExpressRoute")]
    [string]$gatewayType,
    [string]$gatewaySize,
    [int]$asn
)
Import-Module "$($PSScriptRoot)\IPNetworkingPS.dll"
. "$($PSScriptRoot)\foundationsObjects.ps1"
Import-Module "$($PSScriptRoot)\Newtonsoft.Json.Schema.dll"
Import-Module "$($PSScriptRoot)\Newtonsoft.Json.dll"

<##
$customerAbv = "test"

$cloud = "mac"
$deploymentAddressSpace = "10.0.0.0/17"
$templateRootPath = "F:\ARM Foundations Test\"
$deployGateways = $true

$gatewayType = "VPN"
$gatewaySize = "VpnGw1"
$asn = 65800
##>
$path = $templateRootPath
$check = Get-Item -Path $path
if($check -eq $null)
{
    New-Item -Path $path -ItemType directory
}

$enrollmentAddressSpace = $deploymentAddressSpace

$subscriptionConfigs = ConvertFrom-Json -InputObject ($(Get-Content -Path "$($PSScriptRoot)\subscriptions.json") -join "`n")
$schema = [Newtonsoft.Json.Schema.JSchema]::Parse(($(Get-Content -Path "$($PSScriptRoot)\FoundationsTemplate-SubscriptionJson-Validation.json") -join "`n"))
$jObject = [Newtonsoft.Json.Linq.JArray]::Parse(($(Get-Content -Path "$($PSScriptRoot)\subscriptions.json") -join "`n"))
$errorWarning = @"
    Bad Subscriptions File! Validate each entry has the following parameters:
[    
    {
        "isHub":  bool,
        "cider":  int,
        "subnetsCider":  [
                             "strings"
                         ],
        "typeName":  "string",
		"dr": bool,
		"drCider": int,
		"drSubnetsCider": [
                             "strings"
						  ]
    }
]
    subnetsCider and drSubnetsCider should be formated like "Subnet Name/Cider" Example: "DMZ/28"
"@
if(![Newtonsoft.Json.Schema.SchemaExtensions]::IsValid($jObject,$schema))
{
    throw $errorWarning
}
$subscriptionConfigs
$subNamesSlashes = @()
## Regions ##
$locations = @("primary","secondary")
$regionSlash = [int]$enrollmentAddressSpace.Split("/")[1] + 1

$GetIPs = New-Object IPNetworkingPS.IPNetworking($enrollmentAddressSpace)
foreach($location in $locations)
{
    $regionAddressSpace = $GetIPs.ReserveSpace($regionSlash)
    $regionIps = New-Object IPNetworkingPS.IPNetworking($regionAddressSpace)
    if($location -eq "primary")
    {        
        foreach($sub in $subscriptionConfigs)
        {
            if(!$sub.PSobject.Properties.name.Contains("subAddresses"))
            {
                $sub | Add-Member -NotePropertyName subAddresses -NotePropertyValue @()
            }
            $sub.subAddresses += $($sub.typeName + "\" + $regionIps.ReserveSpace($sub.cider) + "\" + $location)
        }
    }
    else
    {
        foreach($sub in $subscriptionConfigs)
        {
            if(!$sub.PSobject.Properties.name.Contains("subAddresses"))
            {
                $sub | Add-Member -NotePropertyName subAddresses -NotePropertyValue @()
            }
            if($sub.dr -eq $true)
            {
                $sub.subAddresses += $($sub.typeName + "\" + $regionIps.ReserveSpace($sub.drCider) + "\" + $location)
            }
        }
    }
}

$subscriptions = @()
$gatewayIds = @()
$gatewaysConfigured = $false

$GetIPs = $null

## Recovery Services Vaults ##
foreach ($sub in $subscriptionConfigs)
{
	foreach ($location in $locations)
	{
        if($location -eq "primary")
        {
            $recoveryPath = $path + $sub.typeName +"\Recovery\" + $location + "\"
            $recoveryDir = Get-Item -Path $recoveryPath
            if($recoveryDir -eq $null)
            {
                New-Item -Path $recoveryPath -ItemType Directory
            }
            $recoveryNested = ConvertFrom-Json -InputObject $($jsonMaster)
            $parameters = ConvertFrom-Json -InputObject $jsonParameters
            $recoveryNested.parameters | Add-Member -NotePropertyName Name -NotePropertyValue @{ type = "string"; defaultValue = $("[concat('" + $sub.typeName.ToLower() + "','-',resourceGroup().location)]"); metadata = "Name of Recovery Vault" }
		    $vault = ConvertFrom-Json -InputObject $($jsonRecoveryVault -f "[parameters('Name')]")
		    $recoveryNested.resources += $vault
            ConvertTo-Json -Depth 100 -InputObject $recoveryNested | Out-File "$($recoveryPath + "Recovery-" + $sub.typeName + "-Template-" + $location.ToLower() ).json"
        }
        elseif($sub.dr -eq $true)
        {
            $recoveryPath = $path + $sub.typeName +"\Recovery\" + $location + "\"
            $recoveryDir = Get-Item -Path $recoveryPath
            if($recoveryDir -eq $null)
            {
                New-Item -Path $recoveryPath -ItemType Directory
            }
            $recoveryNested = ConvertFrom-Json -InputObject $($jsonMaster)
            $parameters = ConvertFrom-Json -InputObject $jsonParameters
            $recoveryNested.parameters | Add-Member -NotePropertyName Name -NotePropertyValue @{ type = "string"; defaultValue = $("[concat('" + $sub.typeName.ToLower() + "','-',resourceGroup().location)]"); metadata = "Name of Recovery Vault" }
		    $vault = ConvertFrom-Json -InputObject $($jsonRecoveryVault -f "[parameters('Name')]")
		    $recoveryNested.resources += $vault
            ConvertTo-Json -Depth 100 -InputObject $recoveryNested | Out-File "$($recoveryPath + "Recovery-" + $sub.typeName + "-Template-" + $location.ToLower() ).json"
            
        }       
	}
}
## End ##

## Subnet Configs ##
foreach($sub in $subscriptionConfigs)
{
    foreach($subAddress in $sub.subAddresses)
    {
        $number = 0
        $subnetsSlashes = @()
        $subnetsAddresses = @()
        
        $GetIPs = New-Object IPNetworkingPS.IPNetworking($subAddress.Split("\")[1])
        if($subAddress.Split("\")[2] -eq "primary")
        {
            foreach($subnetsSlash in $sub.subnetsCider)
            {
                if($subnetsSlash.split("/")[0] -ne "GatewaySubnet" -and $subnetsSlash.split("/")[0] -ne "AzureBastionSubnet")
                {
                    $number += 10
                    $subnetsAddresses += "[concat('" + $subnetsSlash.split("/")[0] + "_" + $sub.typeName + "_" + $number +"_',resourceGroup().location)]\" + $GetIPs.ReserveSpace([int]$subnetsSlash.Split("/")[1])
                }
                elseif($subnetsSlash.split("/")[0] -eq "AzureBastionSubnet")
                {
                    $count = $GetIPs.GetCiderCount([int]$subnetsSlash.split("/")[1])
                    $octet = $getIPs.GetOctect([int]$subnetsSlash.split("/")[1])
                    $subnetsAddresses += "AzureBastionSubnet\" +  $GetIPs.ReserveSpace(27)
                }
                else
                {
                    $count = $GetIPs.GetCiderCount([int]$subnetsSlash.split("/")[1])
                    $octet = $getIPs.GetOctect([int]$subnetsSlash.split("/")[1])
                    $subnetsAddresses += "GatewaySubnet\" +  $GetIPs.ReserveSpace(27)
                }
            }
        }
        elseif($sub.dr -eq $true)
        {
            foreach($subnetsSlash in $sub.drSubnetsCider)
            {
                if($subnetsSlash.split("/")[0] -ne "GatewaySubnet" -and $subnetsSlash.split("/")[0] -ne "AzureBastionSubnet")
                {
                    $number += 10
                    $subnetsAddresses += "[concat('" + $subnetsSlash.split("/")[0] + "_" + $sub.typeName + "_" + $number +"_',resourceGroup().location)]\" + $GetIPs.ReserveSpace([int]$subnetsSlash.Split("/")[1])
                }
                elseif($subnetsSlash.split("/")[0] -eq "AzureBastionSubnet")
                {
                    $count = $GetIPs.GetCiderCount([int]$subnetsSlash.split("/")[1])
                    $octet = $getIPs.GetOctect([int]$subnetsSlash.split("/")[1])
                    $subnetsAddresses += "AzureBastionSubnet\" +  $GetIPs.ReserveSpace(27)
                }
                else
                {
                    $count = $GetIPs.GetCiderCount([int]$subnetsSlash.split("/")[1])
                    $octet = $getIPs.GetOctect([int]$subnetsSlash.split("/")[1])
                    $subnetsAddresses += "GatewaySubnet\" +  $GetIPs.ReserveSpace(27)
                }
            }
        }
        
        $subscriptions += New-Object -TypeName psobject -Property @{
            subscriptionName = $sub.typeName
            location = $subAddress.Split("\")[2]
            vnetName = $("vnet_" + $subAddress.split("\")[0].ToLower() + "_")
            addressSpace = @($subAddress.split("\")[1])
            subnets = $subnetsAddresses
        }
    }
}
## End ##

$uniqueSubs = $subscriptions.subscriptionName | Select -Unique

$vnets = @()

foreach($sub in $uniqueSubs)
{
    $subscriptionsByLocation = $subscriptions | ?{$_.subscriptionName -eq $sub}
    foreach($subscription in $subscriptionsByLocation)
    {
        $networkingPath = $($path + $subscription.subscriptionName + "\Networking\" + $subscription.location + "\")  
        $pathCheck = Get-Item -Path $networkingPath
        if($pathCheck -eq $null)
        {
            New-Item -Path $networkingPath -ItemType Directory
        }
        $vnetMaster = ConvertFrom-Json -InputObject $jsonMaster
        $vnetMaster.parameters | Add-Member -NotePropertyName VNetName -NotePropertyValue @{type = "string"; defaultValue = $("[concat('" + $subscription.vnetName + "',resourceGroup().location)]"); metadata = "Name of Virtual Network"}
        $vnetMaster.parameters | Add-Member -NotePropertyName VNetAddressSpace -NotePropertyValue @{type = "array"; defaultValue = $subscription.addressSpace; metadata = "Address Space of Virtual Network"}
        $vnet = ConvertFrom-Json -InputObject $($jsonVnet -f "parameters('VNetName')",$(ConvertTo-Json -InputObject "[parameters('VNetAddressSpace')]"))
        $count = 1
        foreach($subnet in $subscription.subnets)
        {            
            $nsgName = $subnet.Split("\")[0].replace("concat('","concat('NSG_")
            $nsgParameter = $("NSG" + $count)
            $nsgId = $("[resourceId('Microsoft.Network/networkSecurityGroups', parameters('$($nsgParameter)'))]")
            $subnetName = $subnet.Split("\")[0]
            $vnetMaster.parameters | Add-Member -NotePropertyName $nsgParameter -NotePropertyValue @{type = "string"; defaultValue = $nsgName; metadata = "Name of NSG for $($subnetName)"}
            if($subnetName.Contains("GatewaySubnet"))
            {
                $subnetName = "GatewaySubnet"
            }
            if($subnetName.Contains("AzureBastionSubnet"))
            {
                $subnetName = "AzureBastionSubnet"
            }
            $subnetAddress = $subnet.Split("\")[1]
            if($subnetName -ne "GatewaySubnet" -and $subnetName -ne "AzureBastionSubnet")
            {
                if($nsgName.contains("DMZ"))
                {
                    $nsg = ConvertFrom-Json -InputObject $($jsonNewtorkSecurityGroup -f "[parameters('$($nsgParameter)')]")
                    $nsg.properties.securityRules += ConvertFrom-Json -InputObject $jsonNetworkSecurityRulesDMZ
                }
                else
                {
                    $nsg = ConvertFrom-Json -InputObject $($jsonNewtorkSecurityGroup -f "[parameters('$($nsgParameter)')]")
                }
                $subnetParameter = "Subnet" + $count
                $vnetMaster.parameters | Add-Member -NotePropertyName $subnetParameter -NotePropertyValue @{type = "string"; defaultValue = $subnetName; metadata = "Subnet: $($subnetName)"}
                $vnetMaster.parameters | Add-Member -NotePropertyName $($subnetParameter + "AddressSpace") -NotePropertyValue @{type = "string"; defaultValue = $subnetAddress; metadata = "Address Space for Subnet: $($subnetName)"}
                $vnet.properties.subnets += ConvertFrom-Json -InputObject $($jsonSubnet -f "[parameters('$($subnetParameter)')]", "[parameters('$($subnetParameter + "AddressSpace")')]", $nsgId)
                $vnet.dependsOn += $nsgId
                $vnetMaster.resources += $nsg
                $count++
            }            
            elseif($subnetName -eq "AzureBastionSubnet")
            {
                $subnetParameter = "Subnet" + $count
                $vnetMaster.parameters | Add-Member -NotePropertyName $subnetParameter -NotePropertyValue @{type = "string"; defaultValue = $subnetName; metadata = "Subnet: $($subnetName)"}
                $vnetMaster.parameters | Add-Member -NotePropertyName $($subnetParameter + "AddressSpace") -NotePropertyValue @{type = "string"; defaultValue = $subnetAddress; metadata = "Address Space for Subnet: $($subnetName)"}
                $vnet.properties.subnets += ConvertFrom-Json -InputObject $($jsonSubnetGateway -f $subnetName,$subnetAddress)
                $count++
            }
            else
            {
                if($deployGateways -eq $true)
                {
                    $vnetMaster.parameters | Add-Member -NotePropertyName "Gateway-PublicIP" -NotePropertyValue @{type = "string"; defaultValue = $("[concat(resourceGroup().location,'-gw-pip')]"); metadata = "Public IP for Azure Gateway"}
                    $pubIp = ConvertFrom-Json -InputObject $($jsonPubIp -f "[parameters('Gateway-PublicIP')]" )
                    $vnetMaster.resources += $pubIp

                    if($gatewayType -eq "VPN")
                    {
                        $vnetMaster.parameters | Add-Member -NotePropertyName "GatewayName" -NotePropertyValue @{type = "string"; defaultValue = $("[concat(resourceGroup().location,'-gw')]"); metadata = "Azure Gateway Name"}
                        $gateway = ConvertFrom-Json -InputObject $($jsonGatewayVPN -f "[parameters('GatewayName')]",$("'Microsoft.Network/virtualNetworks/subnets', replace(replace(parameters('VNetName'),'[',''),']',''), '" + $subnetName + "'"),$("'Microsoft.Network/publicIpAddresses', parameters('Gateway-PublicIP')"),$gatewayType,"RouteBased",$gatewaySize,$gatewaySize,$asn)
                        $gateway.dependsOn = @("[resourceId('Microsoft.Network/virtualNetworks', replace(replace(parameters('VNetName'),'[',''),']',''))]","[resourceId('Microsoft.Network/publicIpAddresses', parameters('Gateway-PublicIP'))]")
                        $asn++
						$vnetMaster.resources += $gateway
					}
                    else
                    {
                        $vnetMaster.parameters | Add-Member -NotePropertyName "GatewayName" -NotePropertyValue @{type = "string"; defaultValue = $("[concat(resourceGroup().location,'-er')]"); metadata = "Azure Gateway Name"}
                        $gateway = ConvertFrom-Json -InputObject $($jsonGatewayExpressRoute -f "[parameters('GatewayName')]",$("'Microsoft.Network/virtualNetworks/subnets', replace(replace(parameters('VNetName'),'[',''),']',''), '" + $subnetName + "'"),$("'Microsoft.Network/publicIpAddresses', parameters('Gateway-PublicIP')"),$gatewayType,$gatewaySize,$gatewaySize)
                        $gateway.dependsOn = @("[resourceId('Microsoft.Network/virtualNetworks', replace(replace(parameters('VNetName'),'[',''),']',''))]","[resourceId('Microsoft.Network/publicIpAddresses', parameters('Gateway-PublicIP'))]")
                        $asn++
						$vnetMaster.resources += $gateway
                    }
                    $vnetMaster.parameters | Add-Member -NotePropertyName "GatewaySubnetAddressSpace" -NotePropertyValue @{type = "string"; defaultValue = $subnetAddress; metadata = "Address Space for GatewaySubnets"}
					$vnet.properties.subnets += ConvertFrom-Json -InputObject $($jsonSubnetGateway -f $subnetName, "[parameters('GatewaySubnetAddressSpace')]")
				}
			}
		}
        $vnetMaster.resources += $vnet
		ConvertTo-Json -Depth 100 -InputObject $vnetMaster | Out-File "$($networkingPath + "Networking-" + $subscription.subscriptionName + "-" + $subscription.location).json"
		$vnets += New-Object -TypeName psobject -Property @{
            id = $("/subscriptions/" + $subId + "/resourceGroups/" + $subscription.vnetRg + "/providers/Microsoft.Network/virtualNetworks/" + $subscription.vnetName)
            name = $subscription.vnetName
            location = $subscription.location
        }
	}
}