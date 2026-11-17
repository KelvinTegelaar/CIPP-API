function Invoke-ExecOneDriveCopyToUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.OneDrive.ReadWrite
    .DESCRIPTION
        Copies a leaver's OneDrive root contents into a folder named after the leaver's UPN at the root of each recipient's OneDrive, without overwriting anything already there (KeepBoth on name conflicts). The leaver must already be blocked from signing in. The leaver and recipients must be in tenantFilter; each recipient needs a OneDrive licence, a provisioned OneDrive and enough free space. Returns an OperationId; poll ListOneDriveCopyToUser with it until State is Completed before removing the leaver's licences.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $StatusCode = [HttpStatusCode]::OK

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw [System.ArgumentException]::new('tenantFilter is required.') }
        if ($TenantFilter -eq 'AllTenants') { throw [System.ArgumentException]::new('tenantFilter must name a single tenant.') }

        # Plain strings or {label, value} objects from an autocomplete are both accepted.
        $Leaver = $Request.Body.leaver.value ?? $Request.Body.leaver
        if ($Leaver -isnot [string] -or [string]::IsNullOrWhiteSpace($Leaver)) { throw [System.ArgumentException]::new('leaver is required (UPN or object id).') }

        $Recipients = @(foreach ($Recipient in @($Request.Body.recipients)) {
                if ($null -eq $Recipient) { continue }
                $Value = $Recipient.value ?? $Recipient
                if ($Value -is [string]) { $Value -split ',' } else { throw [System.ArgumentException]::new('recipients must be UPNs or object ids.') }
            }) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if (@($Recipients).Count -eq 0) { throw [System.ArgumentException]::new('recipients is required (one or more UPNs or object ids).') }

        $User = try {
            [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json
        } catch { $null }
        $StartedBy = $User.userDetails ?? $Headers.'x-ms-client-principal-name' ?? 'CIPP-API'

        $Params = @{
            TenantFilter          = $TenantFilter
            Leaver                = $Leaver
            Recipients            = @($Recipients)
            IncludeVersionHistory = [bool]($Request.Body.includeVersionHistory -eq $true)
            StartedBy             = $StartedBy
            Headers               = $Headers
            APIName               = $APIName
        }
        $Result = Start-CIPPOneDriveCopyToUser @Params
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to start the OneDrive copy. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
