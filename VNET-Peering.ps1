param (
    [string]$hubSubId,
    [string[]]$spokeSubIds 
)
$vnets = Get-AzVirtualNetwork
$allSpokes = @()
foreach($sub in $spokeSubIds)
{
    Select-AzSubscription $sub
    $spokeVnets = Get-AzVirtualNetwork
    $allSpokes += $spokeVnets
    foreach($spoke in $spokeVnets)
    {
        $hub = $vnets | ?{$_.Location -eq $spoke.location}
        Add-AzVirtualNetworkPeering -Name To-Services -VirtualNetwork $spoke -RemoteVirtualNetworkId $hub.id -AllowForwardedTraffic -UseRemoteGateway
    }
}
Select-AzSubscription $hubSubId
foreach($spoke in $allSpokes)
{
    Add-AzVirtualNetworkPeering -Name $("To-" + $spoke.Name) -VirtualNetwork $($vnets | ?{$_.Location -eq $spoke.Location}) -RemoteVirtualNetworkId $spoke.Id -AllowGatewayTransit
}