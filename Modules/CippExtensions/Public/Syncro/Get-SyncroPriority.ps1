function Get-SyncroPriority {
    <#
    .SYNOPSIS
        Resolves a stored priority setting to the exact string Syncro expects on a ticket.
    .DESCRIPTION
        Syncro has four fixed priorities and its API wants them spelled exactly as it stores
        them: '0 Urgent', '1 High', '2 Normal', '3 Low'. The integration settings page saves
        those strings, but the value can also arrive as the {label, value} autocomplete object
        or as a bare name such as 'High' from an older or hand-edited configuration, so all of
        those forms are accepted.

        A bare digit is deliberately NOT accepted. HaloPSA stores its priorities as small
        integers, and when both PSAs are enabled the per-alert priority on an alert is a Halo
        id - mapping '2' to '2 Normal' would silently pick a Syncro priority the admin never
        chose. Anything that is not a recognisable Syncro priority returns $null so the caller
        can fall through to the next source.
    .PARAMETER Priority
        The stored value in any of the accepted shapes.
    #>
    [CmdletBinding()]
    param (
        $Priority
    )

    $Value = $Priority.value ?? $Priority
    if ($null -eq $Value) { return $null }
    $Text = "$Value".Trim()
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $Known = [ordered]@{
        '0 Urgent' = @('0 Urgent', 'Urgent')
        '1 High'   = @('1 High', 'High')
        '2 Normal' = @('2 Normal', 'Normal')
        '3 Low'    = @('3 Low', 'Low')
    }
    foreach ($Canonical in $Known.Keys) {
        foreach ($Alias in $Known[$Canonical]) {
            if ($Text -ieq $Alias) { return $Canonical }
        }
    }
    return $null
}
