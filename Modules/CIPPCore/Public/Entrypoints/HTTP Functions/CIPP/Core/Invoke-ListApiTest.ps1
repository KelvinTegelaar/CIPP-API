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
    if ($env:DEBUG_ENV_VARS -eq 'true') {
        $BlockedKeys = @('ApplicationSecret', 'RefreshToken', 'AzureWebJobsStorage', 'DEPLOYMENT_STORAGE_CONNECTION_STRING')
        $EnvironmentVariables = [PSCustomObject]@{}
        Get-ChildItem env: | Where-Object { $BlockedKeys -notcontains $_.Name } | ForEach-Object {
            $EnvironmentVariables | Add-Member -NotePropertyName $_.Name -NotePropertyValue $_.Value
        }
        $Response.EnvironmentVariables = $EnvironmentVariables
    }
    $Response.AllowedTenants = $script:AllowedTenants
    $Response.AllowedGroups = $script:AllowedGroups

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Response
        })
}
