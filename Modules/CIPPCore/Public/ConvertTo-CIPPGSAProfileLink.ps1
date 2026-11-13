function ConvertTo-CIPPGSAProfileLink {
    <#
    .SYNOPSIS
        Validates Global Secure Access security profile links and returns them in one shape.
    .DESCRIPTION
        Each link names a filtering policy as {label, value} or as the bare value (a template GUID or a
        tenant policy id), a priority from 100 to 65000 (unique), and a state and loggingState of
        enabled or disabled (both default to enabled). Returns Links and Errors; callers refuse the
        input when Errors has anything in it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([object[]]$Links)

    $Errors = [System.Collections.Generic.List[string]]::new()
    $Output = [System.Collections.Generic.List[object]]::new()
    $LinkedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Priorities = [System.Collections.Generic.HashSet[int]]::new()
    $InputLinks = @($Links).Where({ $null -ne $_ })
    if ($InputLinks.Count -eq 0) { $Errors.Add('link at least one filtering policy') }
    foreach ($Link in $InputLinks) {
        $PolicyId = [string]($Link.policy.value ?? $Link.policy)
        $Priority = $Link.priority -as [int]
        $State = [string]($Link.state ?? 'enabled')
        $LoggingState = [string]($Link.loggingState ?? 'enabled')
        if (-not $PolicyId) { $Errors.Add('every link needs a filtering policy'); continue }
        if (-not $LinkedIds.Add($PolicyId)) { $Errors.Add("filtering policy $PolicyId is linked twice") }
        if ($null -eq $Priority -or $Priority -lt 100 -or $Priority -gt 65000) { $Errors.Add("link priority for $PolicyId must be a number from 100 to 65000") }
        elseif (-not $Priorities.Add($Priority)) { $Errors.Add("link priority $Priority is used twice") }
        if ($State -notin 'enabled', 'disabled' -or $LoggingState -notin 'enabled', 'disabled') { $Errors.Add("link state and logging for $PolicyId must be enabled or disabled") }
        $Output.Add([ordered]@{ policy = [ordered]@{ label = [string]$Link.policy.label; value = $PolicyId }; priority = $Priority; state = $State; loggingState = $LoggingState })
    }
    [pscustomobject]@{ Links = @($Output); Errors = @($Errors) }
}
