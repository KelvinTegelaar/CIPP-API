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
    }
    $Response.AllowedTenants = $script:CippAllowedTenantsStorage.Value
    $Response.AllowedGroups = $script:CippAllowedGroupsStorage.Value

    # test Get-AzAccessToken vs Get-CIPPAzAccessToken timing with stopwatch
    $Sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Get-AzAccessToken
    $Sw.Stop()
    $Timings = @{}
    $Timings.GetAzAccessTokenMs = $Sw.Elapsed.TotalMilliseconds
    $Sw = [System.Diagnostics.Stopwatch]::StartNew()
    $null = Get-CIPPAzIdentityToken
    $Sw.Stop()
    $Timings.GetCippAzIdentityTokenMs = $Sw.Elapsed.TotalMilliseconds
    $Response.Timings = $Timings

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Response
        })
}
