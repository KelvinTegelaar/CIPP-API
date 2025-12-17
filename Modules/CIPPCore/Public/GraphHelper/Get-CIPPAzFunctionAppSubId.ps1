function Get-CIPPAzFunctionAppSubId {
    <#
    .SYNOPSIS
    Get the subscription ID for the current function app
    .DESCRIPTION
    Get the subscription ID for the current function app
    .EXAMPLE
    Get-CIPPAzFunctionAppSubId
    #>
    [CmdletBinding()]
    param()

    $SubscriptionId = $env:WEBSITE_OWNER_NAME -split '\+' | Select-Object -First 1
    return $SubscriptionId
}
