function Protect-CIPPManagedBaselineSnapshot {
    <#
    .SYNOPSIS
        Removes what could identify a tenant from a value before it is stored for, or sent to, CyberDrain.
    .DESCRIPTION
        Walks one standard's current value. On/off values, numbers, dates and empty values pass.
        A text value becomes '<redacted>' when Test-CIPPManagedBaselineIdentifier finds anything
        in it, and its length when it is longer than 200 characters. Text that appears word for
        word in the standard's own definition always passes, so CIPP's own constants are not
        blanked for containing dots. Property names are checked the same way.
        A list is as likely to name users, mailboxes or devices as to hold settings, so only its
        length is kept unless every entry is an on/off value, a number or the definition's own text.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Value,
        [string[]]$TenantIdentifiers = @(),
        # The standard's definition: every text in it is known not to come from the tenant.
        $Definition
    )

    $Known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Collect = $null
    $Collect = {
        param($Node, $Depth)
        if ($null -eq $Node -or $Depth -gt 25) { return }
        if ($Node -is [string]) { $null = $Known.Add($Node); return }
        if ($Node -is [ValueType]) { return }
        if ($Node -is [System.Collections.IDictionary]) {
            foreach ($Key in @($Node.Keys)) { $null = $Known.Add("$Key"); & $Collect $Node[$Key] ($Depth + 1) }
        } elseif ($Node -is [System.Collections.IEnumerable]) {
            foreach ($Element in $Node) { & $Collect $Element ($Depth + 1) }
        } elseif ($Node -is [System.Management.Automation.PSCustomObject]) {
            foreach ($Property in $Node.PSObject.Properties) { $null = $Known.Add($Property.Name); & $Collect $Property.Value ($Depth + 1) }
        }
    }
    & $Collect $Definition 0

    $Scrub = {
        param([string]$Text)
        if ([string]::IsNullOrEmpty($Text) -or $Known.Contains($Text)) { return $Text }
        if ($Text.Length -gt 200) { return '<text, {0} characters>' -f $Text.Length }
        if (Test-CIPPManagedBaselineIdentifier -Text $Text -TenantIdentifiers $TenantIdentifiers -AnyDomain) { return '<redacted>' }
        $Text
    }
    # Two redacted property names must not collapse into one.
    $NameOf = {
        param([string]$Name, $Taken)
        $Safe = & $Scrub $Name
        $Unique = $Safe
        $Number = 1
        while ($Taken.Contains($Unique)) { $Number++; $Unique = '{0} {1}' -f $Safe, $Number }
        $Unique
    }
    $Walk = $null
    $Walk = {
        param($Node, $Depth)
        if ($null -eq $Node) { return $null }
        if ($Node -is [string]) { return (& $Scrub $Node) }
        if ($Node -is [guid]) { return '<redacted>' }
        if ($Node -is [ValueType]) { return $Node }
        if ($Depth -gt 25) { return '<redacted>' }
        if ($Node -is [System.Collections.IDictionary]) {
            $Out = [ordered]@{}
            foreach ($Key in @($Node.Keys)) { $Out[(& $NameOf "$Key" $Out)] = & $Walk $Node[$Key] ($Depth + 1) }
            return [PSCustomObject]$Out
        }
        if ($Node -is [System.Collections.IEnumerable]) {
            $Elements = @(foreach ($Element in $Node) { $Element })
            $Plain = $Elements.Where({
                    $null -eq $_ -or ($_ -is [ValueType] -and $_ -isnot [guid]) -or ($_ -is [string] -and ($_ -eq '' -or $Known.Contains($_)))
                })
            if ($Plain.Count -eq $Elements.Count) { return , $Elements }
            return '<{0} item{1}>' -f $Elements.Count, ($Elements.Count -eq 1 ? '' : 's')
        }
        if ($Node -is [System.Management.Automation.PSCustomObject]) {
            $Out = [ordered]@{}
            foreach ($Property in $Node.PSObject.Properties) { $Out[(& $NameOf $Property.Name $Out)] = & $Walk $Property.Value ($Depth + 1) }
            return [PSCustomObject]$Out
        }
        & $Scrub "$Node"
    }
    & $Walk $Value 0
}
