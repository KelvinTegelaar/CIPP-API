function Invoke-ListAlertResults {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Alert.Read
    .DESCRIPTION
        Lists the currently-active fired alert items for a tenant, read from the
        AlertLastRun table. AlertLastRun stores the items produced by the most recent
        run of each scripted alert (Get-CIPPAlert*) after snoozed items have already
        been filtered out, so this returns the active (non-snoozed) instances. Each
        item is returned with a content preview/hash (matching the snooze format) and
        the raw alert item so the frontend can snooze it via ExecSnoozeAlert.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'tenantFilter is required.' }
                })
        }

        $Table = Get-CIPPTable -tablename 'AlertLastRun'
        # AlertLastRun: PartitionKey = run date (yyyyMMdd), RowKey = "{tenant}-{cmdlet}"
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type String
        $Rows = Get-CIPPAzDataTableEntity @Table -Filter "Tenant eq '$SafeTenant'"

        # Keep only the most recent run (highest date partition) per alert. RowKey is
        # "{tenant}-{cmdlet}", uniquely identifying the alert for this tenant. Write-AlertTrace
        # only writes a new row when the data changes, so the latest row is the current state.
        $LatestByAlert = @{}
        foreach ($Row in @($Rows)) {
            $Key = $Row.RowKey
            $Existing = $LatestByAlert[$Key]
            if (-not $Existing -or [string]$Row.PartitionKey -gt [string]$Existing.PartitionKey) {
                $LatestByAlert[$Key] = $Row
            }
        }
        $StaleCutoff = [datetime]::UtcNow.AddDays(-7).ToString('yyyyMMdd')

        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($Row in $LatestByAlert.Values) {
            if ([string]$Row.PartitionKey -lt $StaleCutoff) { continue }
            if ([string]::IsNullOrWhiteSpace($Row.LogData)) { continue }
            try {
                $Items = $Row.LogData | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Write-Information "Failed to parse AlertLastRun LogData for $($Row.RowKey): $($_.Exception.Message)"
                continue
            }

            foreach ($Item in @($Items)) {
                if ($null -eq $Item) { continue }
                $Hash = Get-AlertContentHash -AlertItem $Item
                $Results.Add([PSCustomObject]@{
                        CmdletName     = $Row.CmdletName
                        AlertComment   = $Row.AlertComment
                        Tenant         = $Row.Tenant
                        LastRun        = $Row.PartitionKey
                        ContentHash    = $Hash.ContentHash
                        ContentPreview = $Hash.ContentPreview
                        AlertItem      = $Item
                    })
            }
        }

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($Results)
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to list alert results: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Failed to list alert results: $($ErrorMessage.NormalizedError)" }
            })
    }
}
