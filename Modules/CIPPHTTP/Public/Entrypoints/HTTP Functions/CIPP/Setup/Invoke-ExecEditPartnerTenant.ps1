function Invoke-ExecEditPartnerTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.SuperAdmin.ReadWrite
    .DESCRIPTION
        Edits properties of an additional partner tenant. Managed controls whether the partner
        appears as a manageable tenant row in the tenant list (tenant mode governs the primary).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Flag = Get-CIPPFeatureFlag -Id 'MultiPartner'
        if (-not $Flag.Enabled) {
            throw 'The Multiple Partner Tenants feature is not enabled.'
        }
        $null = Get-CIPPAuthentication

        $PartnerTenantId = $Request.Body.partnerTenantId.value ?? $Request.Body.partnerTenantId
        if ($PartnerTenantId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
            throw 'partnerTenantId must be a tenant id (GUID).'
        }
        $Table = Get-CIPPTable -tablename 'PartnerTenants'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Partners' and RowKey eq '$PartnerTenantId'"
        if (-not $Row -and $PartnerTenantId -eq $env:TenantID) {
            # The primary's row is seeded lazily - create it so the property has a home
            $Row = [PSCustomObject]@{
                PartitionKey    = 'Partners'
                RowKey          = "$env:TenantID"
                partnerTenantId = "$env:TenantID"
                displayName     = '*Partner Tenant'
                Enabled         = $true
            }
        }
        if (-not $Row) {
            throw "Partner tenant $PartnerTenantId is not configured."
        }

        $Results = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $Request.Body.Managed) {
            # Arrives as a string from the action dialog; [bool]'false' would be $true
            $Managed = "$($Request.Body.Managed)" -in @('true', '1')
            $Row | Add-Member -MemberType NoteProperty -Name 'Managed' -Value $Managed -Force
            Add-CIPPAzDataTableEntity @Table -Entity $Row -Force | Out-Null
            if ($Managed) {
                # The partner row appears on the next tenant refresh - queue one now
                $InputObject = [PSCustomObject]@{
                    Batch            = @(@{ FunctionName = 'UpdateTenants' })
                    OrchestratorName = 'UpdateTenants'
                    SkipLog          = $true
                }
                $null = Start-CIPPOrchestrator -InputObject $InputObject
                $Results.Add("Partner tenant $($Row.displayName) will appear in the tenant list after the queued refresh completes.")
            } else {
                $TenantsTable = Get-CIPPTable -tablename 'Tenants'
                $TenantRow = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$PartnerTenantId'"
                if ($TenantRow) {
                    Remove-CIPPAzDataTableEntity -Force @TenantsTable -Entity $TenantRow
                }
                $null = Clear-CippTokenCache -TenantFilter $PartnerTenantId
                $Results.Add("Partner tenant $($Row.displayName) removed from the tenant list.")
            }
            Write-LogMessage -API 'ExecEditPartnerTenant' -headers $Request.Headers -message "Set Managed=$Managed for partner tenant $PartnerTenantId" -Sev 'Info'
        }
        if ($Results.Count -eq 0) {
            $Results.Add('No changes requested.')
        }
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = @($Results) }
    } catch {
        Write-LogMessage -API 'ExecEditPartnerTenant' -headers $Request.Headers -message "Failed to edit partner tenant: $($_.Exception.Message)" -LogData (Get-CippException -Exception $_) -sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = @("Failed to edit partner tenant: $($_.Exception.Message)") }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}
