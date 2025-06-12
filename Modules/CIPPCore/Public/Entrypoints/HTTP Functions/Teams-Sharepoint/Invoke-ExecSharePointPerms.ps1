using namespace System.Net

Function Invoke-ExecSharePointPerms {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $tenantFilter = $Request.Body.tenantFilter
    $Headers = $Request.Headers

    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev Debug

    Write-Host '===================================='
    Write-Host 'Request Body:'
    Write-Host (ConvertTo-Json $Request.body -Depth 10)
    Write-Host '===================================='


    # The UPN or ID of the users OneDrive we are changing permissions on
    $UserId = $Request.Body.UPN
    # The UPN of the user we are adding or removing permissions for
    $OnedriveAccessUser = $Request.Body.onedriveAccessUser.value ?? $Request.Body.user.value
    $URL = $Request.Body.URL
    $RemovePermission = $Request.Body.RemovePermission

    try {

        $State = Set-CIPPSharePointPerms -tenantFilter $tenantFilter `
            -UserId $UserId `
            -OnedriveAccessUser $OnedriveAccessUser `
            -Headers $Headers `
            -APIName $APIName `
            -RemovePermission $RemovePermission `
            -URL $URL
        $Result = "$State"
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed. $($ErrorMessage.NormalizedError)"
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}
