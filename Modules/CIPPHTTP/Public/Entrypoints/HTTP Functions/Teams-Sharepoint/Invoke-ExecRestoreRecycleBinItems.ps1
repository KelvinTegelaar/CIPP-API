function Invoke-ExecRestoreRecycleBinItems {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.SiteRecycleBin.ReadWrite
    .DESCRIPTION
        Restores one or more items from a SharePoint site's recycle bin via the SharePoint
        REST API RestoreByIds method with certificate authentication.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $Ids = @($Request.Body.Ids) | Where-Object { $_ }
    $ItemNames = @($Request.Body.ItemNames) | Where-Object { $_ }

    try {
        if (-not $SiteUrl) { throw 'SiteUrl is required.' }
        if ($Ids.Count -eq 0) { throw 'No recycle bin items were selected.' }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $Scope = "$($SharePointInfo.SharePointUrl)/.default"
        $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
        $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

        $RestoreBody = ConvertTo-Json -Compress -Depth 5 -InputObject @{ ids = @($Ids) }
        try {
            $null = New-GraphPostRequest -uri "$BaseUri/site/RecycleBin/RestoreByIds" -tenantid $TenantFilter -scope $Scope -type POST -body $RestoreBody -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
        } catch {
            throw "RestoreByIds failed: $($_.Exception.Message)"
        }

        $Label = if ($ItemNames.Count -gt 0) { $ItemNames -join ', ' } else { "$($Ids.Count) item(s)" }
        $Results = "Successfully restored $Label from the recycle bin of $SiteUrl."
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to restore recycle bin items on $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}
