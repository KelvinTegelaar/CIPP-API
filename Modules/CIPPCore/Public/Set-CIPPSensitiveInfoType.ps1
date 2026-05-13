function Set-CIPPSensitiveInfoType {
    <#
    .SYNOPSIS
        Deploy or update a single custom Sensitive Information Type in a tenant from a template object.
    .DESCRIPTION
        Single source of truth for SIT deployment, shared by the HTTP deploy endpoint and the standard.
        Supports simple mode (Pattern → backend synthesizes rule pack XML) and advanced mode (caller-
        supplied FileDataBase64 rule pack). Microsoft built-in SITs are skipped.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TenantFilter,
        [Parameter(Mandatory)] $Template,
        [Parameter(Mandatory)] [string] $APIName,
        $Headers
    )

    $Name = $Template.Name

    # Build FileData byte array from either advanced (FileDataBase64) or simple (Pattern) mode
    $FileDataBytes = $null
    if ($Template.FileDataBase64) {
        try {
            $FileDataBytes = [System.Convert]::FromBase64String($Template.FileDataBase64)
        } catch {
            $msg = "SIT '$Name' has invalid FileDataBase64 ($($_.Exception.Message)) — skipping in $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error
            return $msg
        }
    } elseif ($Template.Pattern) {
        $Xml = New-CIPPSitRulePackXml `
            -Name $Name `
            -Description ($Template.Description ?? '') `
            -Pattern $Template.Pattern `
            -Confidence ([int]($Template.Confidence ?? 85)) `
            -PatternsProximity ([int]($Template.PatternsProximity ?? 300)) `
            -Locale ($Template.Locale ?? 'en-us') `
            -PublisherName ($Template.PublisherName ?? 'CIPP')
        $FileDataBytes = [System.Text.Encoding]::UTF8.GetBytes($Xml)
    } else {
        $msg = "SIT '$Name' is missing both 'Pattern' and 'FileDataBase64' — skipping in $TenantFilter."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error
        return $msg
    }

    try {
        $ExistingSits = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationType' -Compliance | Select-Object Name, Publisher } catch { @() }
        $Existing = $ExistingSits | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

        if ($Existing -and $Existing.Publisher -like 'Microsoft*') {
            $msg = "SIT '$Name' is a Microsoft built-in and cannot be modified — skipping in $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Warning
            return $msg
        }

        $CmdletParams = @{ FileData = $FileDataBytes }
        if (-not [string]::IsNullOrWhiteSpace([string]$Template.Description)) { $CmdletParams['Description'] = $Template.Description }
        if (-not [string]::IsNullOrWhiteSpace([string]$Template.Locale)) { $CmdletParams['Locale'] = $Template.Locale }

        if ($Existing) {
            $CmdletParams['Identity'] = $Name
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DlpSensitiveInformationType' -cmdParams $CmdletParams -Compliance -useSystemMailbox $true
            $action = "Updated SIT '$Name' in $TenantFilter."
        } else {
            $CmdletParams['Name'] = $Name
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpSensitiveInformationType' -cmdParams $CmdletParams -Compliance -useSystemMailbox $true
            $action = "Created SIT '$Name' in $TenantFilter."
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $action -sev Info
        return $action
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $msg = "Could not deploy SIT '$Name' to $($TenantFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error -LogData $ErrorMessage
        return $msg
    }
}
