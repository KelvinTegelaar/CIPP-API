function Invoke-ExecSetOneDriveSharing {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.SharePoint.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Body.tenantFilter
    $UserPrincipalName = $Request.Body.UPN
    $SharingCapability = $Request.Body.SharingCapability.value ?? $Request.Body.SharingCapability

    try {
        $Result = Set-CIPPOneDriveSharing `
            -UserId $UserPrincipalName `
            -TenantFilter $TenantFilter `
            -SharingCapability $SharingCapability `
            -APIName $APIName `
            -Headers $Request.Headers

        $Body = @{ Results = $Result }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to set OneDrive sharing: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $Body = @{ Results = "Failed to set OneDrive sharing: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
