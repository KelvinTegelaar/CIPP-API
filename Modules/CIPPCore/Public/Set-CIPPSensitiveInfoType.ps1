function Set-CIPPSensitiveInfoType {
    <#
    .SYNOPSIS
        Deploy or update a single custom Sensitive Information Type in a tenant from a template object.
    .DESCRIPTION
        Single source of truth for SIT deployment, shared by the HTTP deploy endpoint and the standard.
        Imports a custom SIT *rule package* (regex/keyword based, Type=Entity) via
        New-/Set-DlpSensitiveInformationTypeRulePackage. Supports simple mode (Pattern -> backend
        synthesizes the rule pack XML) and advanced mode (caller-supplied FileDataBase64 rule pack,
        e.g. captured from an existing SIT). Microsoft built-in SITs are skipped.

        IMPORTANT: this uses the rule-*package* cmdlets, NOT New-/Set-DlpSensitiveInformationType - the
        latter is a document-fingerprint primitive that stores -FileData as a fingerprint and discards
        the regex. The rule pack XML must use the 2011 'mce' schema and be UTF-16 encoded.
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

    # Resolve the rule pack XML from advanced (FileDataBase64) or simple (Pattern) mode.
    $XmlString = $null
    if ($Template.FileDataBase64) {
        try {
            $RawBytes = [System.Convert]::FromBase64String($Template.FileDataBase64)
        } catch {
            $msg = "SIT '$Name' has invalid FileDataBase64 ($($_.Exception.Message)) - skipping in $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error
            return $msg
        }
        # Captured/synthesized packs are UTF-16; fall back to UTF-8 if that doesn't look like the XML.
        $XmlString = [System.Text.Encoding]::Unicode.GetString($RawBytes)
        if ($XmlString -notmatch '<RulePackage') { $XmlString = [System.Text.Encoding]::UTF8.GetString($RawBytes) }
    } elseif ($Template.Pattern) {
        $XmlString = New-CIPPSitRulePackXml `
            -Name $Name `
            -Description ($Template.Description ?? '') `
            -Pattern $Template.Pattern `
            -Confidence ([int]($Template.Confidence ?? 85)) `
            -PatternsProximity ([int]($Template.PatternsProximity ?? 300)) `
            -Locale ($Template.Locale ?? 'en-US') `
            -PublisherName ($Template.PublisherName ?? 'CIPP')
    } else {
        $msg = "SIT '$Name' is missing both 'Pattern' and 'FileDataBase64' - skipping in $TenantFilter."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Error
        return $msg
    }

    try {
        $ExistingSits = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DlpSensitiveInformationType' -Compliance | Select-Object Name, Publisher, RulePackId } catch { @() }
        $Existing = $ExistingSits | Where-Object { $_.Name -eq $Name } | Select-Object -First 1

        if ($Existing -and $Existing.Publisher -like 'Microsoft*') {
            $msg = "SIT '$Name' is a Microsoft built-in and cannot be modified - skipping in $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Warning
            return $msg
        }
        # A same-named SIT already living in the shared fingerprint pack would force a Set against that
        # pack, replacing ALL its fingerprints. Refuse rather than risk wiping unrelated SITs - the
        # existing one was created by uploading a document and must be managed that way.
        if ($Existing -and $Existing.RulePackId -eq '00000000-0000-0000-0001-000000000001') {
            $msg = "SIT '$Name' already exists as a document-fingerprint in the shared managed pack and cannot be safely overwritten by a rule-pack deploy - skipping in $TenantFilter."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $msg -sev Warning
            return $msg
        }

        if ($Existing) {
            # Update in place: Set-* identifies the pack to replace from the XML's RulePack id (it has no
            # -Identity parameter), so rewrite the id to point at the existing pack, then pass FileData only.
            $PackId = $Existing.RulePackId
            $XmlString = $XmlString -replace '(?i)(<RulePack\s+id=")[^"]*(")', ('${1}' + $PackId + '${2}')
            $FileDataBytes = [System.Text.Encoding]::Unicode.GetBytes($XmlString)
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DlpSensitiveInformationTypeRulePackage' -cmdParams @{ FileData = $FileDataBytes } -Compliance -useSystemMailbox $true
            $action = "Updated SIT '$Name' in $TenantFilter."
        } else {
            $FileDataBytes = [System.Text.Encoding]::Unicode.GetBytes($XmlString)
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-DlpSensitiveInformationTypeRulePackage' -cmdParams @{ FileData = $FileDataBytes } -Compliance -useSystemMailbox $true
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
