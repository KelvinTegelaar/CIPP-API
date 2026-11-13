function Get-CIPPStatsMobileEnrollment {
    [CmdletBinding()]
    param()

    try {
        $MobileEnrollment = 0
        $Fields = [string[]]@('operatingSystem')
        # Through MethodInfo.Invoke: PowerShell copies a large string passed straight to a method several times per call
        $ParseJson = [CIPP.CippJson].GetMethod('ConvertFromJson', [type[]]@([string], [string[]]))
        foreach ($Tenant in (Get-Tenants -IncludeErrors).defaultDomainName) {
            if ([string]::IsNullOrWhiteSpace($Tenant)) { continue }
            foreach ($Row in (Get-CIPPDbItem -Partition $Tenant -Type 'ManagedDevices')) {
                if (-not $Row.Data) { continue }
                $Parsed = try { $ParseJson.Invoke($null, [object[]]@([string]$Row.Data, $Fields)) } catch { $null }
                foreach ($Device in @($Parsed)) {
                    if ([string]$Device.operatingSystem -match 'iOS|iPadOS|Android') { $MobileEnrollment++ }
                }
            }
        }

        return $MobileEnrollment
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to calculate MobileEnrollment: $($_.Exception.Message)" -sev Warning
        return 0
    }
}
