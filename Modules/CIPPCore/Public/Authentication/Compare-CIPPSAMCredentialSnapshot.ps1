function Compare-CIPPSAMCredentialSnapshot {
    <#
    .SYNOPSIS
        Diffs the CIPP-SAM app's credentials against the stored snapshot and alerts on changes.
    .DESCRIPTION
        Raises one alert per added or removed secret/certificate through every configured
        notification channel, then stores the new snapshot. The first run only stores.
        Every change alerts, including CIPP's own: -Acknowledge takes keyIds of changes CIPP itself
        just made so they are worded as expected (-AcknowledgeNote) rather than as something to review.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string[]]$Acknowledge = @(),
        [string]$AcknowledgeNote,
        $CredentialState
    )

    $State = $CredentialState ?? (Get-CIPPSAMCredentials)
    $Current = @($State.Credentials | ForEach-Object {
            [pscustomobject]@{
                keyId       = $_.keyId
                displayName = $_.displayName
                type        = $_.type
                thumbprint  = $_.thumbprint
                endDateTime = $_.endDateTime
                owner       = $_.owner
                source      = $_.source
                actor       = $_.actor
            }
        })

    $Table = Get-CIPPTable -tablename 'Config'
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SAMCredentialSnapshot' and RowKey eq 'Snapshot'"

    $Changes = [System.Collections.Generic.List[object]]::new()
    if ($Row) {
        $Previous = @(([string]$Row.Snapshot | ConvertFrom-Json -ErrorAction SilentlyContinue))
        $PreviousIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Previous.keyId | Where-Object { $_ }))
        $CurrentIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Current.keyId | Where-Object { $_ }))
        foreach ($Credential in $Current) {
            if (-not $PreviousIds.Contains([string]$Credential.keyId)) { $Changes.Add(($Credential | Select-Object @{ n = 'change'; e = { 'added' } }, *)) }
        }
        foreach ($Credential in $Previous) {
            if ($Credential.keyId -and -not $CurrentIds.Contains([string]$Credential.keyId)) { $Changes.Add(($Credential | Select-Object @{ n = 'change'; e = { 'removed' } }, *)) }
        }
    }

    $null = Add-CIPPAzDataTableEntity @Table -Entity @{
        PartitionKey = 'SAMCredentialSnapshot'
        RowKey       = 'Snapshot'
        Snapshot     = [string](ConvertTo-Json -InputObject @($Current) -Depth 3 -Compress)
    } -Force

    foreach ($Change in $Changes) {
        $Identifier = if ($Change.type -eq 'Certificate' -and $Change.thumbprint) { "thumbprint $($Change.thumbprint)" } else { "keyId $($Change.keyId)" }
        $SourceText = switch ($Change.source) { 'ScheduledRotation' { 'scheduled rotation' } 'Manual' { "manual, by $($Change.actor)" } 'Setup' { "setup, by $($Change.actor)" } default { $null } }
        $Own = $Change.keyId -in $Acknowledge
        $Provenance = if ($Own -and $AcknowledgeNote) {
            "$AcknowledgeNote No action needed."
        } elseif ($Own -and $Change.change -eq 'removed') {
            'Credential removed by this CIPP instance. No action needed.'
        } elseif ($Change.change -eq 'removed') {
            'Credential removed outside this CIPP instance; review it.'
        } elseif ($SourceText) {
            "Created by CIPP ($SourceText). No action needed."
        } elseif ($Change.owner -eq 'thisInstance') {
            'Created by this CIPP instance. No action needed.'
        } else {
            'New credential detected - not created by this CIPP instance; review it.'
        }
        $Title = "CIPP-SAM $($Change.type.ToLower()) $($Change.change): $($Change.displayName)"
        Write-LogMessage -API 'SAM Credential Monitor' -tenant 'Global' -message "$Provenance $Title ($Identifier, owner $($Change.owner), expires $($Change.endDateTime))" -Sev 'Info'
        $Detail = [pscustomobject]@{
            Change      = $Change.change
            Provenance  = $Provenance
            Name        = $Change.displayName
            Type        = $Change.type
            Identifier  = $Identifier
            Owner       = $Change.owner
            Expires     = $Change.endDateTime
            Application = $State.ApplicationId
        }
        $Html = "<p>$Provenance</p>$(($Detail | ConvertTo-Html -Fragment | Out-String))"
        $Json = ConvertTo-Json -InputObject ([pscustomobject]@{ title = $Title; data = $Detail }) -Depth 3 -Compress
        foreach ($Channel in 'email', 'psa', 'webhook') {
            try {
                if ($Channel -eq 'webhook') {
                    $null = Send-CIPPAlert -Type $Channel -Title $Title -JSONContent $Json -TenantFilter $env:TenantID -APIName 'SAM Credential Monitor'
                } else {
                    $null = Send-CIPPAlert -Type $Channel -Title $Title -HTMLContent $Html -TenantFilter $env:TenantID -APIName 'SAM Credential Monitor'
                }
            } catch {
                Write-LogMessage -API 'SAM Credential Monitor' -tenant 'Global' -message "Could not send $Channel alert for '$Title': $($_.Exception.Message)" -Sev 'Warning'
            }
        }
    }
    return $Changes
}
