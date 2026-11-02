function ConvertTo-CIPPPIMRoleSettings {
    <#
    .SYNOPSIS
        Normalises PIM role settings from a request body or stored template into the canonical shape.

    .DESCRIPTION
        The template editor posts autoComplete fields as { label, value } objects and switches as
        booleans (or 'true'/'false' strings after a JSON round trip). Everything that consumes a
        template - the floor check, the rule converter, the standard - works on this one flat
        shape with ISO 8601 durations and real booleans, so the unwrapping lives here once.

        Unknown properties are dropped; missing ones take the secure defaults so an older
        template keeps validating after new settings are introduced.

    .PARAMETER InputObject
        A hashtable or PSCustomObject with any subset of the settings properties.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $InputObject
    )

    function Get-Scalar {
        param($Value)
        if ($null -eq $Value) { return $null }
        if ($Value -is [string] -or $Value -is [bool] -or $Value -is [System.ValueType]) { return $Value }
        if ($Value -is [System.Collections.IDictionary]) {
            if ($Value.Contains('value')) { return $Value['value'] }
            return $null
        }
        if ($Value.PSObject.Properties['value']) { return $Value.value }
        return "$Value"
    }

    function Get-Bool {
        param($Value, [bool]$Default)
        $Scalar = Get-Scalar $Value
        if ($null -eq $Scalar -or "$Scalar" -eq '') { return $Default }
        if ($Scalar -is [bool]) { return $Scalar }
        return ("$Scalar" -match '^(true|1|yes)$')
    }

    function Get-Text {
        param($Value, [string]$Default = '')
        $Scalar = Get-Scalar $Value
        if ($null -eq $Scalar) { return $Default }
        $Text = "$Scalar".Trim()
        if ($Text -eq '') { return $Default }
        return $Text
    }

    function Get-Prop {
        param($Object, [string]$Name)
        if ($null -eq $Object) { return $null }
        if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
        return $Object.$Name
    }

    # A multi-select of recipients/approvers may arrive as an array of strings or label/value objects.
    function Get-List {
        param($Value)
        if ($null -eq $Value) { return '' }
        if ($Value -is [string]) { return $Value.Trim() }
        if ($Value -is [System.Collections.IEnumerable]) {
            return (@($Value | ForEach-Object { Get-Text $_ } | Where-Object { $_ }) -join ', ')
        }
        return (Get-Text $Value)
    }

    $Source = $InputObject

    [PSCustomObject]@{
        activationMaxDuration                 = Get-Text (Get-Prop $Source 'activationMaxDuration') 'PT8H'
        activationRequires                    = Get-Text (Get-Prop $Source 'activationRequires') 'MFA'
        authenticationContextClaimValue       = Get-Text (Get-Prop $Source 'authenticationContextClaimValue')
        activationRequiresJustification       = Get-Bool (Get-Prop $Source 'activationRequiresJustification') $true
        activationRequiresTicket              = Get-Bool (Get-Prop $Source 'activationRequiresTicket') $false
        activationRequiresApproval            = Get-Bool (Get-Prop $Source 'activationRequiresApproval') $false
        approvers                             = Get-List (Get-Prop $Source 'approvers')
        eligibilityMaxDuration                = Get-Text (Get-Prop $Source 'eligibilityMaxDuration') 'P365D'
        activeAssignmentMaxDuration           = Get-Text (Get-Prop $Source 'activeAssignmentMaxDuration') 'P180D'
        activeAssignmentRequiresMfa           = Get-Bool (Get-Prop $Source 'activeAssignmentRequiresMfa') $true
        activeAssignmentRequiresJustification = Get-Bool (Get-Prop $Source 'activeAssignmentRequiresJustification') $true
        notificationRecipients                = Get-List (Get-Prop $Source 'notificationRecipients')
        notificationLevel                     = Get-Text (Get-Prop $Source 'notificationLevel') 'All'
    }
}
