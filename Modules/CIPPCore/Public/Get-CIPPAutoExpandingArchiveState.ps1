function Get-CIPPAutoExpandingArchiveState {
    <#
    .FUNCTIONALITY
        Internal
    .SYNOPSIS
        Resolves effective Auto Expanding Archive state for a mailbox.
    .DESCRIPTION
        Organization-level enablement overrides the per-mailbox setting.
        Returns AutoExpandingArchive (bool) and AutoExpandingArchiveScope
        (Organization | Mailbox | None).

        Inputs are coerced safely: PowerShell's [bool] cast treats any non-empty
        string (including "False") as $true, so string/JSON values are parsed explicitly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $MailboxAutoExpandingArchiveEnabled = $false,

        [Parameter(Mandatory = $false)]
        $OrgAutoExpandingArchiveEnabled = $false
    )

    function ConvertTo-SafeBool {
        param($Value)

        if ($Value -is [bool]) {
            return $Value
        }
        if ($null -eq $Value) {
            return $false
        }

        $Parsed = $false
        if ([bool]::TryParse("$Value", [ref]$Parsed)) {
            return $Parsed
        }

        $StringValue = "$Value".Trim().ToLowerInvariant()
        return ($StringValue -eq '1' -or $StringValue -eq 'yes')
    }

    $MailboxEnabled = ConvertTo-SafeBool $MailboxAutoExpandingArchiveEnabled
    $OrgEnabled = ConvertTo-SafeBool $OrgAutoExpandingArchiveEnabled

    if ($OrgEnabled) {
        return @{
            AutoExpandingArchive      = $true
            AutoExpandingArchiveScope = 'Organization'
        }
    }

    if ($MailboxEnabled) {
        return @{
            AutoExpandingArchive      = $true
            AutoExpandingArchiveScope = 'Mailbox'
        }
    }

    return @{
        AutoExpandingArchive      = $false
        AutoExpandingArchiveScope = 'None'
    }
}
