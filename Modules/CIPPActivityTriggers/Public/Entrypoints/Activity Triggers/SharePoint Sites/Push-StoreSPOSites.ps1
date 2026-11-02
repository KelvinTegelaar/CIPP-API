function Push-StoreSPOSites {
    <#
    .SYNOPSIS
        Post-execution function that writes the SPOSites cache from the per-batch site reads.

    .DESCRIPTION
        Writes every row the batches returned in one Add-CIPPDbItem call, so its orphan cleanup stays
        authoritative. A site that did not come back this run keeps its previous row: when every batch
        returned, only sites in the run's URL list are carried over (a deleted site falls out); when a
        batch is missing, every previous row not refreshed is kept, because the missing batch's URLs
        are unknown. A run that returned no rows leaves the cache untouched.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter
    $TotalBatches = [int]$Item.Parameters.TotalBatches

    try {
        $Expected = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Fresh = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Rows = [System.Collections.Generic.List[object]]::new()
        $Returned = 0
        foreach ($Batch in @($Item.Results)) {
            if (-not $Batch) { continue }
            $Returned++
            foreach ($Url in @($Batch.Urls)) { $null = $Expected.Add("$Url") }
            foreach ($Site in @($Batch.Sites)) {
                if (-not $Site) { continue }
                $Rows.Add($Site)
                $null = $Fresh.Add("$($Site.Url)")
            }
        }

        if ($Rows.Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SPOSites: no sites read this run ($Returned of $TotalBatches batches returned); prior cache left untouched" -sev Error
            return
        }

        $Complete = $Returned -ge $TotalBatches
        $Carried = 0
        foreach ($Prior in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SPOSites')) {
            $Url = "$($Prior.Url)"
            if (-not $Url -or $Fresh.Contains($Url)) { continue }
            if (-not $Complete -or $Expected.Contains($Url)) {
                $Rows.Add($Prior)
                $Carried++
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOSites' -Data $Rows -AddCount
        if ($Carried -gt 0 -or -not $Complete) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "SPOSites: $($Fresh.Count) sites refreshed, $Carried carried over from the previous run ($Returned of $TotalBatches batches returned)" -sev Warning
        }
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to store SharePoint site settings: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
