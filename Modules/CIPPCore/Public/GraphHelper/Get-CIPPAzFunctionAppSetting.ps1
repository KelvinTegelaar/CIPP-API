function Get-CIPPAzFunctionAppSetting {
    <#
    .SYNOPSIS
        Retrieves Azure Function App application settings via ARM REST using managed identity.
    .PARAMETER Name
        Function App name.
    .PARAMETER ResourceGroupName
        Resource group name.
    .PARAMETER AccessToken
        Optional bearer token to override Managed Identity. If provided, this token is used for Authorization.
    .EXAMPLE
        Get-CIPPAzFunctionAppSetting -Name myfunc -ResourceGroupName rg1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken
    )

    $subscriptionId = Get-CIPPAzFunctionAppSubId
    $apiVersion = '2024-11-01'
    $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Web/sites/$Name/config/appsettings/list?api-version=$apiVersion"

    # ARM peculiarity: listing appsettings can require POST on some endpoints
    $restParams = @{ Uri = $uri; Method = 'POST' }
    if ($AccessToken) { $restParams.AccessToken = $AccessToken }
    $resp = New-CIPPAzRestRequest @restParams
    return $resp
}
