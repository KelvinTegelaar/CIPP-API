function Get-CIPPMaintenanceNotice {
    <#
    .SYNOPSIS
    Build the hosted maintenance notice alert from the CIPP_MAINTENANCE_NOTICE environment variable.

    .DESCRIPTION
    Hosted deployments announce planned maintenance by setting CIPP_MAINTENANCE_NOTICE to a JSON
    object. This returns it shaped as a GetCippAlerts alert, or $null when there is nothing to show.

    Only 'message' is required. Everything else falls back to a default rather than failing, and the
    notice suppresses itself once 'end' has passed so the variable never needs to be un-set.

    This runs on every page load for every user, so it never throws and never touches Graph or table
    storage - bad input is logged and treated as "no notice".

    .EXAMPLE
    $env:CIPP_MAINTENANCE_NOTICE = '{"message":"Planned maintenance.","end":"2026-08-24T06:00:00Z"}'
    Get-CIPPMaintenanceNotice
    #>
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:CIPP_MAINTENANCE_NOTICE)) { return $null }

    try {
        $Notice = $env:CIPP_MAINTENANCE_NOTICE | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Information "CIPP_MAINTENANCE_NOTICE is not valid JSON, ignoring it: $($_.Exception.Message)"
        return $null
    }

    if ($Notice -is [array]) {
        # Only one notice is supported - take the first rather than dropping the lot.
        $Notice = $Notice | Select-Object -First 1
    }

    # Scalars only. A nested object would otherwise reach the UI as "@{a=1}".
    $AsText = {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [string]) { return $Value }
        if ($Value -is [array] -or $Value -is [hashtable] -or $Value -is [System.Management.Automation.PSCustomObject]) { return $null }
        return [string]$Value
    }

    $Message = & $AsText $Notice.message
    if ([string]::IsNullOrWhiteSpace($Message)) {
        Write-Information 'CIPP_MAINTENANCE_NOTICE has no usable "message", ignoring it.'
        return $null
    }

    # An unparseable date is dropped rather than fatal - a typo in the window shouldn't hide the notice.
    $ParseDate = {
        param($Value, $FieldName)
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        try {
            return [datetime]::Parse(
                $Value,
                [cultureinfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
            )
        } catch {
            Write-Information "CIPP_MAINTENANCE_NOTICE has an unparseable '$FieldName' value '$Value', ignoring that field."
            return $null
        }
    }

    $Start = & $ParseDate $Notice.start 'start'
    $End = & $ParseDate $Notice.end 'end'
    $Now = [datetime]::UtcNow

    # Past the window - stop emitting so hosted ops don't have to clear the variable afterwards.
    if ($null -ne $End -and $Now -gt $End) { return $null }

    $Active = $null -ne $Start -and $Now -ge $Start

    $ValidSeverities = @('info', 'warning', 'error')
    $RawSeverity = & $AsText $Notice.severity
    $Severity = if ([string]::IsNullOrWhiteSpace($RawSeverity)) {
        'info'
    } elseif ($RawSeverity.ToLower() -in $ValidSeverities) {
        $RawSeverity.ToLower()
    } else {
        Write-Information "CIPP_MAINTENANCE_NOTICE has an unrecognized severity '$RawSeverity', defaulting to info."
        'info'
    }

    $RawTitle = & $AsText $Notice.title
    $Title = if (-not [string]::IsNullOrWhiteSpace($RawTitle)) {
        $RawTitle
    } elseif ($Active) {
        'Maintenance in progress'
    } else {
        'Scheduled Maintenance'
    }

    $Link = & $AsText $Notice.link
    if ([string]::IsNullOrWhiteSpace($Link)) { $Link = $null }

    # Notices that are a call to action deserve a verb on the button, not "Details".
    $LinkText = & $AsText $Notice.linkText
    if ([string]::IsNullOrWhiteSpace($LinkText)) { $LinkText = 'Details' }

    # The id scopes the frontend's dismissal, so re-issuing an edited notice un-dismisses it for
    # everyone. Without an explicit one, hash the content so any edit produces a new key.
    $RawId = & $AsText $Notice.id
    $Id = if (-not [string]::IsNullOrWhiteSpace($RawId)) {
        $RawId
    } else {
        $Fingerprint = '{0}|{1}|{2}|{3}' -f $Notice.title, $Message, $Notice.start, $Notice.end
        $Sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $Bytes = $Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Fingerprint))
            -join ($Bytes[0..5] | ForEach-Object { $_.ToString('x2') })
        } finally {
            $Sha.Dispose()
        }
    }

    return @{
        title       = $Title
        Alert       = $Message
        link        = $Link
        linkText    = $LinkText
        type        = $Severity
        maintenance = $true
        noticeId    = $Id
        startTime   = if ($null -eq $Start) { $null } else { $Start.ToString('o') }
        endTime     = if ($null -eq $End) { $null } else { $End.ToString('o') }
        active      = $Active
        dismissible = $Notice.dismissible -ne $false
    }
}
