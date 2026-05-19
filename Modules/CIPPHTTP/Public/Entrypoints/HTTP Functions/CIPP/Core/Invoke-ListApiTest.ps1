function Invoke-ListApiTest {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Response = @{}
    $Response.Request = $Request
    $Response.TriggerMetadata = $TriggerMetadata
    if ($env:DEBUG_ENV_VARS -eq 'true') {
        $BlockedKeys = @('ApplicationSecret', 'RefreshToken', 'AzureWebJobsStorage', 'DEPLOYMENT_STORAGE_CONNECTION_STRING')
        $EnvironmentVariables = [PSCustomObject]@{}
        Get-ChildItem env: | Where-Object { $BlockedKeys -notcontains $_.Name } | ForEach-Object {
            $EnvironmentVariables | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value
        }
        $Response.EnvironmentVariables = $EnvironmentVariables

        # test New-CIPPAzRestRequest KQL for resource graph
        $Query = 'Resources | project name, type'
        $Json = ConvertTo-Json -Depth 10 -Compress -InputObject @{ query = $Query }
        $Request = New-CIPPAzRestRequest -Method POST -Resource 'https://management.azure.com/' -Uri 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01' -Body $Json
        $Response.ResourceGraphTest = $Request
    }
    $Response.AllowedTenants = $script:CippAllowedTenantsStorage.Value
    $Response.AllowedGroups = $script:CippAllowedGroupsStorage.Value

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Response
        })
}
