function Set-CIPPGroupLicense {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$GroupId,
        [string]$GroupName,
        [array]$AddLicenses = @(),
        [array]$RemoveLicenses = @(),
        [switch]$Replace,
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        $Headers,
        $APIName = 'Set Group License'
    )

    $AddLicenses = @(
    $AddLicenses |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $RemoveLicenses = @(
    $RemoveLicenses |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ( [string]::IsNullOrWhiteSpace($GroupName)) {
        $GroupName = $GroupId
    }

    # fetch current assigned licenses, calculate the diff and replace with licenses
    if ($Replace.IsPresent) {
        try {
            $Current = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)?`$select=assignedLicenses" -tenantid $TenantFilter
            $CurrentSkus = @($Current.assignedLicenses.skuId)
            $RemoveLicenses = @($CurrentSkus | Where-Object { $_ -notin $AddLicenses })
            $AddLicenses = @($AddLicenses | Where-Object { $_ -notin $CurrentSkus })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API $APIName -tenant $TenantFilter -Headers $Headers -message "Failed to fetch current licenses for group $GroupName. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            throw "Failed to fetch current licenses for group $GroupName. Error: $($ErrorMessage.NormalizedError)"
        }
    }

    if ($AddLicenses.Count -eq 0 -and $RemoveLicenses.Count -eq 0) {
        return @("No license changes required for group $GroupName.")
    }

    $AddLicensesArray = foreach ($SkuId in $AddLicenses) {
        @{ disabledPlans = @(); skuId = $SkuId }
    }
    $LicenseBody = @{
        addLicenses = @($AddLicensesArray)
        removeLicenses = @($RemoveLicenses)
    } | ConvertTo-Json -Compress -Depth 10

    $Results = [System.Collections.Generic.List[string]]::new()
    try {
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)/assignLicense" -tenantid $TenantFilter -body $LicenseBody -type POST

        if ($AddLicenses.Count -gt 0) {
            $Message = "Assigned licenses to group $GroupName. Added: $($AddLicenses -join ', ')"
            [void]$Results.Add("$Message. It may take 2-5 minutes for changes to apply to members.")
            Write-LogMessage -API $APIName -tenant $TenantFilter -Headers $Headers -message $Message -Sev Info
        }
        if ($RemoveLicenses.Count -gt 0) {
            $Message = "Removed licenses from group $GroupName. Removed: $($RemoveLicenses -join ', ')"
            [void]$Results.Add("$Message. It may take 2-5 minutes for changes to apply to members.")
            Write-LogMessage -API $APIName -tenant $TenantFilter -Headers $Headers -message $Message -Sev Info
        }
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -Headers $Headers -message "Failed to update licenses for group $GroupName. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        throw "Failed to update licenses for group $GroupName. Error: $($ErrorMessage.NormalizedError)"
    }
}
