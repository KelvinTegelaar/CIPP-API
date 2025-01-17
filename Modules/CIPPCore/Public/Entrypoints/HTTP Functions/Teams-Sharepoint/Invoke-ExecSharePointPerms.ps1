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

    $APIName = $TriggerMetadata.FunctionName
    $tenantFilter = $Request.Body.tenantFilter
    $ExecutingUser = $Request.Headers.'x-ms-client-principal'

    Write-LogMessage -user $ExecutingUser -API $APIName -message 'Accessed this API' -Sev Debug

    # The UPN or ID of the users OneDrive we are changing permissions on
    $UserId = $Request.body.UPN
    # The UPN of the user we are adding or removing permissions for
    $OnedriveAccessUser = $Request.body.onedriveAccessUser.value

    try {

        $State = Set-CIPPSharePointPerms -tenantFilter $tenantFilter `
            -UserId $UserId `
            -OnedriveAccessUser $OnedriveAccessUser `
            -ExecutingUser $ExecutingUser `
            -APIName $APIName `
            -RemovePermission $Request.body.RemovePermission `
            -URL $Request.Body.URL
        $Results = [pscustomobject]@{'Results' = "$State" }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = [pscustomobject]@{'Results' = "Failed. $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}
